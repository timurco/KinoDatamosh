Shader "Hidden/Kino/Damosh"
{
    Properties
    {
        _MainTex("Main Texture", 2D) = "white" {}
        _PrevTex("Previous Texture", 2D) = "black" {}
    }

    CGINCLUDE   

    #include "UnityCG.cginc"

    sampler2D _MainTex;
    sampler2D _PrevTex;

    float4 _MainTex_TexelSize;
    float _BlockSize;

    // PRNG
    float UVRandom(float2 uv)
    {
        float f = dot(float2(12.9898, 78.233), uv);
        return frac(43758.5453 * sin(f));
    }

    // Vertex shader for multi texturing
    struct v2f_multitex
    {
        float4 pos : SV_POSITION;
        float2 uv0 : TEXCOORD0;
        float2 uv1 : TEXCOORD1;
    };

    v2f_multitex vert_multitex(appdata_full v)
    {
        v2f_multitex o;
        o.pos = UnityObjectToClipPos(v.vertex);
        o.uv0 = v.texcoord.xy;
        o.uv1 = v.texcoord.xy;
    #if UNITY_UV_STARTS_AT_TOP
        if (_MainTex_TexelSize.y < 0.0)
            o.uv1.y = 1.0 - v.texcoord.y;
    #endif
        return o;
    }

    #define LOD 0.0
    #define FRAMES 1.0
    #define halfSize 5.0

    float lum( float4 col ) {
        return dot( col, float4(0.333, 0.333, 0.333, 0.0));
    }

    // Trace function
    float tr2(float2x2 A) {
        return A[0][0] + A[1][1];
    }

    // Determinant function
    float det(float2x2 A) {
        return (A[0][0] * A[1][1]) - (A[1][0] * A[0][1]);
    }

    // Eigenvalues function
    float2 eigenValues(float2x2 A) {
        float m = 0.5 * tr2(A);
        float p = det(A);
        return float2(m + sqrt(m * m - p), m - sqrt(m * m - p));
    }

    float2x2 inverse2x2(float2x2 m) {
        float det = m[0][0] * m[1][1] - m[0][1] * m[1][0];
        if (abs(det) < 1e-6) {
            return float2x2(0, 0, 0, 0); // Return zero matrix in case of near-zero determinant
        }
        float invDet = 1.0 / det;

        return float2x2( m[1][1] * invDet, -m[0][1] * invDet,
                       -m[1][0] * invDet,  m[0][0] * invDet);
    }

    // Initialization shader
    half4 frag_init(v2f_img i) : SV_Target
    {
        return 0;
    }

    // Initialization shader
    half4 frag_vectors(v2f_img i) : SV_Target
    {
        fixed4 currentColor = tex2D(_MainTex, i.uv);
        fixed4 previousColor = tex2D(_PrevTex, i.uv);
                
        // Сравнение текущего и предыдущего кадра
        fixed4 diff = abs(currentColor - previousColor);

        return diff;
    }

    float4 frag_derivatives(v2f_img i) : SV_Target
    {
        float2 uv = i.uv;
        float2 texelLod = pow(2., LOD) / _MainTex_TexelSize.zw;

        float4 N = tex2D(_MainTex, uv + float2( 0., 1.) * texelLod);
        float4 E = tex2D(_MainTex, uv + float2( 1., 0.) * texelLod);
        float4 S = tex2D(_MainTex, uv + float2( 0.,-1.) * texelLod);
        float4 W = tex2D(_MainTex, uv + float2(-1., 0.) * texelLod);

        float cur = lum(tex2D(_MainTex, uv));
        float pre = tex2D(_PrevTex, uv).a;

        // Temporal denoising
        cur = lerp(pre, cur, 1./(1.+ FRAMES));

        float dIdx = lum( (E - W)/2. );
        float dIdy = lum( (N - S)/2. );
        float dIdt = cur - pre;

        float diff = lum(tex2D(_MainTex, uv)) - lum(tex2D(_PrevTex, uv));

        return float4(dIdx, dIdy, dIdt, cur);
    }

    float4 frag_of_lucaskanade(v2f_img i) : SV_Target
    {
        float2 uv = i.uv;
        float2 texel = 1.0 / _ScreenParams.xy;
            
        float2x2 structureTensor = float2x2(0.0, 0.0, 0.0, 0.0);
        float2 Atb = float2(0.0, 0.0);
        for(float i = -halfSize; i < halfSize; i++) {
            for(float j = -halfSize; j < halfSize; j++) {
                float2 loc = uv + float2(i, j) * texel;
                float2 dis = loc - uv;
                float weight = exp(-dot(dis, dis) / 3.0);
                float4 deriv = tex2D(_MainTex, loc);
                structureTensor += float2x2(weight * deriv.x * deriv.x, weight * deriv.x * deriv.y, weight * deriv.x * deriv.y, weight * deriv.y * deriv.y);
                Atb -= float2(weight * deriv.x * deriv.z, weight * deriv.y * deriv.z);
            }
        }
        float2 motion = mul(inverse2x2(structureTensor), Atb);
            
        // Remove bad features
        float2 e = eigenValues(structureTensor);
        if(e.x < 0.001 || e.y < 0.001) {
            motion = float2(0.0, 0.0);
        } 
            
        return float4(motion, 0.0, 1.0);
    }


    ENDCG

    SubShader
    {
        Cull Off ZWrite Off ZTest Always
        Pass
        {
            CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment frag_init
            #pragma target 3.0
            ENDCG
        }
        Pass
        {
            CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment frag_vectors
            #pragma target 3.0
            ENDCG
        }
        Pass
        {
            CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment frag_derivatives
            #pragma target 3.0
            ENDCG
        }
        Pass
        {
            CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment frag_of_lucaskanade
            #pragma target 3.0
            ENDCG
        }
    }
}

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
    sampler2D _DispTex;

    float4 _MainTex_TexelSize;
    float4 _DispTex_TexelSize;

    float _BlockSize;
    float _HalfSize;
    float _Denoise;
    float _Quality;
    float _Diffusion;
    float _Contrast;
    float _Velocity;
    float _LOD;
    float _EigenMin;

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

    // From: https://gist.github.com/983/e170a24ae8eba2cd174f
    float3 hsv2rgb(float3 c)
    {
        float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
        float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
        return c.z * lerp(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
    }

    float4 vectorToHue(float2 mv) {
        float mag = length(mv.xy);
        float ang = atan2(mv.y, mv.x)/(2.*3.14159) + .5;
    
        // Remove noisey small values and scale down
        mag *= 0.5 * smoothstep(0., 1., mag);
    
        float3 col = float3( ang, 1., mag );
        col = hsv2rgb(col);
        return float4(col.r, col.g, col.b, 1.0);
    }

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
    // 3Blue1Brown https://www.youtube.com/watch?v=e50Bj7jn9IQ
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
        float2 texelLod = pow(2., _LOD) / _MainTex_TexelSize.zw;

        float4 N = tex2D(_MainTex, uv + float2( 0., 1.) * texelLod);
        float4 E = tex2D(_MainTex, uv + float2( 1., 0.) * texelLod);
        float4 S = tex2D(_MainTex, uv + float2( 0.,-1.) * texelLod);
        float4 W = tex2D(_MainTex, uv + float2(-1., 0.) * texelLod);

        float cur = lum(tex2D(_MainTex, uv));
        float pre = tex2D(_PrevTex, uv).a;

        // Temporal denoising
        cur = lerp(pre, cur, 1./(1.+ _Denoise));

        float dIdx = lum( (E - W)/2. );
        float dIdy = lum( (N - S)/2. );
        float dIdt = cur - pre;

        return float4(dIdx, dIdy, dIdt, cur);
    }

    float4 frag_of_lucaskanade(v2f_img i) : SV_Target
    {
        //float r = tex2D(_MainTex, i.uv).b*10.0;
        //return float4(r,r,r,1.0);

        float2 uv = i.uv;
        float2 texel = _MainTex_TexelSize.xy;
        
        float2x2 structureTensor = float2x2(0.0, 0.0, 0.0, 0.0);
        float2 Atb = float2(0.0, 0.0);
        for(float i = -_HalfSize; i < _HalfSize; i++) {
            for(float j = -_HalfSize; j < _HalfSize; j++) {
                float2 loc = uv + float2(i, j) * texel;
                float2 dis = loc - uv;
                float weight = exp(-dot(dis, dis) / 3.0);
                float4 deriv = tex2D(_MainTex, loc);
                structureTensor += float2x2(weight * deriv.x * deriv.x, weight * deriv.x * deriv.y, weight * deriv.x * deriv.y, weight * deriv.y * deriv.y);
                Atb -= float2(weight * deriv.x * deriv.z, weight * deriv.y * deriv.z);
            }
        }
        float2 mv = mul(inverse2x2(structureTensor), Atb);

        // Remove bad features
        float2 e = eigenValues(structureTensor);
        if(e.x < _EigenMin || e.y < _EigenMin) {
            mv = float2(0.0, 0.0);
        }

        return float4(mv, 0.0, 1.0);
    }

    float4 frag_update(v2f_img i) : SV_Target
    {
        float2 uv = i.uv;
        // ----------------------------
        float2 t0 = float2(_Time.y, 0);
        float3 rand = float3(
            UVRandom(uv + t0.xy),
            UVRandom(uv + t0.yx),
            UVRandom(uv.yx - t0.xx)
        );
        // ---------------------------
        float2 mv = tex2D(_DispTex, uv).rg;
        mv *= _Velocity;

        // Normalized screen space -> Pixel coordinates
        mv *= _ScreenParams.xy;

        // Small random displacement (diffusion)
        mv += (rand.xy - 0.5) * _Diffusion;

        // Pixel perfect snapping
        mv = round(mv);

        // Accumulates the amount of motion.
        half acc = tex2D(_MainTex, uv).a;
        half mv_len = length(mv);
        // - Simple update
        half acc_update = acc + min(mv_len, _BlockSize) * 0.005;
        acc_update += rand.z * lerp(-0.02, 0.02, _Quality);
        // - Reset to random level
        half acc_reset = rand.z * 0.5 + _Quality;
        // - Reset if the amount of motion is larger than the block size.
        acc = saturate(mv_len > _BlockSize ? acc_reset : acc_update);

        // Pixel coordinates -> Normalized screen space
        mv *= (_ScreenParams.zw - 1);

        //mv *= tex2D(_MainTex, uv).b;

        // Random number (changing by motion)
        half mrand = UVRandom(uv + mv_len);
            
        return half4(mv, mrand, acc);
    }

    // Moshing shader
    half4 frag_mosh(v2f_multitex i) : SV_Target
    {
        // Color from the original image
        half4 src = tex2D(_MainTex, i.uv1);

        // Displacement vector (x, y, random, acc)
        half4 disp = tex2D(_DispTex, i.uv0);

        // Color from the working buffer (slightly scaled to make it blurred)
        half3 work = tex2D(_PrevTex, i.uv1 - disp.xy * 0.98).rgb;

        // Generate some pseudo random numbers.
        float4 rand = frac(float4(1, 17.37135, 841.4272, 3305.121) * disp.z);

        // Generate noise patterns that look like DCT bases.
        // - Frequency
        float2 uv = i.uv1 * _DispTex_TexelSize.zw * (rand.x * 80 / _Contrast);
        // - Basis wave (vertical or horizontal)
        float dct = cos(lerp(uv.x, uv.y, 0.5 < rand.y));
        // - Random amplitude (the high freq, the less amp)
        dct *= rand.z * (1 - rand.x) * _Contrast;

        // Conditional weighting
        // - DCT-ish noise: acc > 0.5
        float cw = (disp.w > 0.5) * dct;
        // - Original image: rand < (Q * 0.8 + 0.2) && acc == 1.0
        cw = lerp(cw, 1, rand.w < lerp(0.2, 1, _Quality) * (disp.w > 0.999));
        // - If the conditions above are not met, choose work.

        float3 res;
        res.r = lerp(work, src.rgb, cw * 0.3).r;
        res.g = lerp(work, src.rgb, cw * 0.7).g;
        res.b = lerp(work, src.rgb, cw).b;


        return half4(res, src.a);
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
        Pass
        {
            CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment frag_update
            #pragma target 3.0
            ENDCG
        }
        Pass
        {
            CGPROGRAM
            #pragma vertex vert_multitex
            #pragma fragment frag_mosh
            #pragma target 3.0
            ENDCG
        }
    }
}

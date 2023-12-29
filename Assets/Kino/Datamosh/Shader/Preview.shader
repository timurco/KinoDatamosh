Shader "Hidden/Kino/Preview"
{
    Properties
    {
        _MainTex("", 2D) = "white"{}
    }

    CGINCLUDE

    #include "UnityCG.cginc"

    sampler2D _MainTex;
    float4 _MainTex_TexelSize;
    int _ViewMode = 0;
    float _Intensity = 1.0f;

    // From: https://gist.github.com/983/e170a24ae8eba2cd174f
    float3 hsv2rgb(float3 c)
    {
        float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
        float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
        return c.z * lerp(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
    }

    float4 vectorToHue(float2 mv) {
        float mag = length(mv.xy) * 2.0;
        float ang = atan2(mv.y, mv.x)/(2.*3.14159) + .5;
    
        // Remove noisey small values and scale down
        //mag *= 0.5 * smoothstep(0., 1., mag);
    
        float3 col = float3( ang, 1., mag );
        col = hsv2rgb(col);
        return float4(col.r, col.g, col.b, 1.0);
    }

    float4 frag_update(v2f_img i) : SV_Target
    {
        float4 col = tex2D(_MainTex, i.uv);
        switch (_ViewMode) {
            case 1:
                return float4(col.xy, 0.0, 1.0) * _Intensity;
            case 2:
                return vectorToHue(col.xy) * _Intensity;
            case 3:
                return col.a * _Intensity;
        }
        
        return col;
    }

    ENDCG

    SubShader
    {
        Cull Off ZWrite Off ZTest Always
        Pass
        {
            CGPROGRAM
            #pragma vertex vert_img
            #pragma fragment frag_update
            #pragma target 3.0
            ENDCG
        }
    }
}

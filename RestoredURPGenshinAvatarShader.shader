Shader "RestoredURPGenshinAvaterShader"
{
    Properties
    {
        [Header(Surface)]
        [MainTexture]_BaseMap("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor("Color", Color) = (1, 1, 1, 1)
        [Toggle(_IsDay)] _IsDay("Is Day", Float) = 1

        [Header(Face)]
        [Toggle(_IS_FACE)] _IsFace("Is Face", Float) = 0
        _FaceLightMap("Face Light Map", 2D) = "white" {}
        _FaceShadowMask("Face Shadow Mask", 2D) = "white" {}
        _FaceDirection("Face Direction", Vector) = (0, 0, 1, 0)
        _FaceBlusher("Face Blusher", Float) = 0
        _FaceBlusherColor("Face Blusher Color", Color) = (1, 1, 1, 1)

        [Header(Shadow)]
        _LightMap("Light Map", 2D) = "white" {}
        _ShadowRamp("Shadow Ramp", 2D) = "white" {}
        _ShadowBorder("Shadow Border", Float) = 0
        _ShadowSmoothness("Shadow Smoothness", Float) = 0
        _ShadowDirection("Shadow Direction", Float) = 1

        [Header(Specular)]
        _MetalMap("MetalMap", 2D) = "white" {}
        _SpecularBorder("Specular Border", Float) = 0
        _Glossiness("Glossiness", Float) = 0
        _Metallic("Metallic", Float) = 0

        [Header(Emission)]
        _EmissionColor("Emission Color", Color) = (1, 1, 1, 1)
        _EmissionIntensity("Emission Intensity", Float) = 0

        [Header(Rim Light)]
        _RimBorder("Rim Border", Float) = 1
        _RimIntensity("Rim Intensity", Float) = 1
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline" = "UniversalPipeline"
            "UniversalMaterialType" = "Lit"
            "RenderType" = "Opaque"
        }

        Pass
        {
            Name "Shading"
            Tags {"LightMode" = "UniversalForward"}

            Cull Back
            ZWrite On
            Blend One Zero

            HLSLPROGRAM

            #pragma shader_feature_local_fragment _IS_FACE

            #pragma vertex ShadingPassVertex
            #pragma fragment ShadingPassFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_LightMap); SAMPLER(sampler_LightMap);
            TEXTURE2D(_FaceLightMap); SAMPLER(sampler_FaceLightMap);
            TEXTURE2D(_FaceShadowMask); SAMPLER(sampler_FaceShadowMask);
            TEXTURE2D(_ShadowRamp); SAMPLER(sampler_ShadowRamp);
            TEXTURE2D(_MetalMap); SAMPLER(sampler_MetalMap);

            CBUFFER_START(UnityPerMaterial)

            half4 _BaseColor;
            half _IsDay;

            half4 _FaceBlusherColor;
            half _FaceBlusher;
            half3 _FaceDirection;

            half _ShadowFactor;
            half _ShadowBorder;
            half _ShadowSmoothness;
            half _ShadowDirection;

            half _SpecularBorder;
            half _Glossiness;
            half _Metallic;

            half4 _EmissionColor;
            half _EmissionIntensity;

            half _RimBorder;
            half _RimIntensity;

            CBUFFER_END

            struct Attributes
            {
                float2 uv : TEXCOORD0;
                half4 color : COLOR;
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                half4 color : COLOR;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float4 positionCS : SV_POSITION;
            };

            Varyings ShadingPassVertex(Attributes input)
            {
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS);

                Varyings output = (Varyings)0;

                output.uv = input.uv;
                output.color = input.color;
                output.positionWS = vertexInput.positionWS;
                output.normalWS = normalInput.normalWS;
                output.positionCS = vertexInput.positionCS;

                return output;
            }

            half GetShadow(Varyings input, half3 L, half occlusionFactor)
            {
                #if _IS_FACE
                half2 lightMap = SAMPLE_TEXTURE2D(_FaceLightMap, sampler_FaceLightMap, input.uv).rg;
                half shadowMask = SAMPLE_TEXTURE2D(_FaceShadowMask, sampler_FaceShadowMask, input.uv).a;
                half3 N = SafeNormalize(half3(_FaceDirection.x, 0.0, _FaceDirection.z));
                half shadow = step(dot(N, L) * - 0.5 + 0.5, lerp(lightMap.r, lightMap.g, step(0.0, cross(N, L).y)));
                half finalShadow = lerp(shadow, 1.0, shadowMask);
                #else
                half halfLambert = dot(input.normalWS, L) * 0.5 + 0.5;
                half shadow = saturate(halfLambert * occlusionFactor * 2.0);
                half finalShadow = lerp(shadow, 1.0, step(1.0, occlusionFactor));
                #endif

                return finalShadow;
            }

            half3 GetRampColor(half shadow, half rampFactor)
            {
                half index = lerp(rampFactor, rampFactor - 0.1, step(1.0, rampFactor)) * 0.5 + lerp(0.05, 0.0, step(0.3, rampFactor)) + 0.5 * _IsDay;
                half2 rampCoord = half2(smoothstep(_ShadowBorder - max(_ShadowSmoothness, 0.0), _ShadowBorder, shadow), index);
                half3 shadowRamp = SAMPLE_TEXTURE2D(_ShadowRamp, sampler_ShadowRamp, rampCoord).rgb;
                half3 finalColor = lerp(shadowRamp, 1.0, step(_ShadowBorder, shadow));

                return finalColor;
            }

            half3 GetSpecular(Varyings input, half3 L, half3 lightColor, half3 albedo, half4 lightMap)
            {
                half2 matcapCoord = SafeNormalize(TransformWorldToViewNormal(input.normalWS)).xy * 0.5 + 0.5;
                half3 metalMap = SAMPLE_TEXTURE2D(_MetalMap, sampler_MetalMap, matcapCoord).rgb;

                half3 R = reflect(- L, input.normalWS);
                half3 V = GetWorldSpaceNormalizeViewDir(input.positionWS);
                half phong = pow(max(dot(R, V), 0.0), max(_Glossiness, 0.0));
                half3 specular = lerp(0.0, max(step(- _SpecularBorder + 2.0, lightMap.b + phong) * _Glossiness * lightColor * 2.0, 0.0), lightMap.b);
                half3 metallicSpecular = max(step(- _SpecularBorder + 2.0, lightMap.b + phong) * _Metallic * metalMap * albedo * 10.0, 0.0);
                half3 finalSpecular = lerp(lerp(specular, metallicSpecular, lightMap.r), specular, step(0.9, lightMap.a));

                return finalSpecular;
            }

            half3 GetRim(Varyings input, half3 lightColor)
            {
                half3 V = GetWorldSpaceNormalizeViewDir(input.positionWS);
                half3 rimLight = lerp(1.0, 0.0, step(_RimBorder, dot(input.normalWS, V))) * max(_RimIntensity, 0.0) * lightColor;

                return rimLight;
            }

            half4 ShadingPassFragment(Varyings input) : COLOR
            {
                half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half emissionFactor = baseMap.a;
                #if _IS_FACE
                half3 albedo = lerp(baseMap.rgb * _BaseColor.rgb, _FaceBlusherColor.rgb, max(emissionFactor * _FaceBlusher, 0));
                half3 emission = 0;
                #else
                half3 albedo = baseMap.rgb * _BaseColor.rgb;
                half3 emission = albedo * emissionFactor * _EmissionColor.rgb * _EmissionIntensity;
                #endif

                half4 lightMap = SAMPLE_TEXTURE2D(_LightMap, sampler_LightMap, input.uv);
                half occlusionFactor = lightMap.g;
                half rampFactor = lightMap.a;

                Light mainLight = GetMainLight();
                half3 lightColor = mainLight.color;
                half3 lightDirection = SafeNormalize(half3(mainLight.direction.x, mainLight.direction.y * _ShadowDirection, mainLight.direction.z));

                half shadow = GetShadow(input, lightDirection, occlusionFactor);
                half3 shadowColor = GetRampColor(shadow, rampFactor);
                half3 specular = GetSpecular(input, lightDirection, lightColor, albedo, lightMap);
                half3 rimLight = GetRim(input, lightColor);
                half3 finalColor = albedo * shadowColor + emission + specular + rimLight;

                return half4(finalColor, 1.0);
            }

            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags {"LightMode" = "ShadowCaster"}

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Off

            HLSLPROGRAM

            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"

            ENDHLSL
        }
    }
}

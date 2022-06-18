Shader "Sinx/ParallaxMapping" {
    Properties {
		[Toggle] _ParallaxMapping("Parallax Mapping", Float) = 0
		[Toggle] _ShareUVs("Share UVs", Float) = 0
		[Space]
        _Color("Color", Color) = (1,1,1,1)
        _MainTex("Main Texture", 2D) = "white" {}
        _Smoothness("Smoothness", Range(0,1)) = 0.5
        _Metallic("Metallic", Range(0,1)) = 0.0
		[Space]
		[Normal] _NormalMap("Normal Map", 2D) = "bump" {}
		//[NoScaleOffset]
		_HeightMap("Height Map", 2D) = "white" {}
		_UVCutoff("UV Cutoff", Vector) = (0, 0, 1, 1)
		_Height("Height", Range(0.0001, 10)) = .1
		[IntRange] _Iters("Iterations", Range(0, 300)) = 50
		//[PowerSlider(10)] _StepSize ("Step Size", Range(0.0001, 1)) = 0.01

    }
    SubShader {
        Tags { "RenderType"="Opaque" }
        LOD 200

        CGPROGRAM
		// Upgrade NOTE: excluded shader from OpenGL ES 2.0 because it uses non-square matrices
		#pragma exclude_renderers gles

        #pragma surface surf Standard fullforwardshadows vertex:vert
        #pragma target 3.0

		bool _ParallaxMapping;
		bool _ShareUVs;

        fixed4 _Color;
        sampler2D _MainTex;
        half _Smoothness;
        half _Metallic;

		sampler2D _NormalMap;
		sampler2D _HeightMap;
		float4 _UVCutoff;
		float _Height;
		int _Iters;
		//float _StepSize;

        struct Input {
            float2 uv_MainTex;
			float2 uv_NormalMap;

			float3 tangentViewDir;
			float3 worldPos;
        };

		void vert(inout appdata_full i, out Input o) {
			UNITY_INITIALIZE_OUTPUT(Input, o);

			//Transform the view direction from world space to tangent space			
			float3 worldVertexPos = mul(unity_ObjectToWorld, i.vertex).xyz;
			o.worldPos = worldVertexPos;
			float3 worldViewDir = worldVertexPos - _WorldSpaceCameraPos;

			//To convert from world space to tangent space we need the following
			//https://docs.unity3d.com/Manual/SL-VertexFragmentShaderExamples.html
			float3 worldNormal = UnityObjectToWorldNormal(i.normal);
			float3 worldTangent = UnityObjectToWorldDir(i.tangent.xyz);
			float3 worldBitangent = cross(worldNormal, worldTangent) * i.tangent.w * unity_WorldTransformParams.w;

			//Use dot products instead of building the matrix
			o.tangentViewDir = float3(
				dot(worldViewDir, worldTangent),
				dot(worldViewDir, worldNormal),
				dot(worldViewDir, worldBitangent)
			);
		}

        UNITY_INSTANCING_BUFFER_START(Props)
        UNITY_INSTANCING_BUFFER_END(Props)

		float4 sampleTex2D(sampler2D tex, float2 uv) {
			return tex2D(tex, uv);
		}

		//Get the height from a uv position
		float getHeight(float2 texturePos) {
			
			return (tex2Dlod(_HeightMap, float4(texturePos, 0, 0)).r - 1) * _Height * .01;
		}

		float3 getNormalFromHeight(float2 texturePos) {
			float epsilon = 0.01;
			float dx = (getHeight(texturePos + float2(-epsilon, 0)) - getHeight(texturePos + float2(epsilon, 0))) / epsilon;
			float dy = (getHeight(texturePos + float2(0, -epsilon)) - getHeight(texturePos + float2(0, epsilon))) / epsilon;
			return normalize(float3(dx, dy, 1));
		}

		//Get the texture position by interpolation between the position where we hit terrain and the position before
		float2 getWeightedTexPos(float3 rayPos, float3 rayDir, float stepDistance) {
			//Move one step back to the position before we hit terrain
			float3 oldPos = rayPos - stepDistance * rayDir;

			float oldHeight = getHeight(oldPos.xz);

			//Always positive
			float oldDistToTerrain = abs(oldHeight - oldPos.y);

			float currentHeight = getHeight(rayPos.xz);

			//Always negative
			float currentDistToTerrain = rayPos.y - currentHeight;

			float weight = currentDistToTerrain / (currentDistToTerrain - oldDistToTerrain);

			//Calculate a weighted texture coordinate
			//If height is -2 and oldHeight is 2, then weightedTex is 0.5, which is good because we should use 
			//the exact middle between the coordinates
			float2 weightedTexPos = oldPos.xz * weight + rayPos.xz * (1 - weight);

			return weightedTexPos;
		}

		float2 parralaxUV(float2 uv, float3 rayDir) {
			if (_ParallaxMapping) {
				//Where is the ray starting? y is up and we always start at the surface
				float3 rayPos = float3(uv.x, 0, uv.y);

				float2 finalUV = uv.xy;
				bool hit = false;
				//float dist = 0;
				bool belowsurface = false;
				float stepDistance = 0.01;

				for (int i = 0; i < _Iters; i++)
				{
					//Get the current height at this uv coordinate
					float height = getHeight(rayPos.xz);

					//If the ray is below the surface
					if ((abs(stepDistance) < .0001) || (i == _Iters - 1)) {

						//Get the texture position by interpolation between the position where we hit terrain and the position before
						float2 weightedTex = getWeightedTexPos(rayPos, rayDir, stepDistance);

						clip(.5 - (weightedTex.x < _UVCutoff.x || weightedTex.x > _UVCutoff.z || weightedTex.y < _UVCutoff.y || weightedTex.y > _UVCutoff.w));

						
						float height = getHeight(weightedTex);

						finalUV = weightedTex;

						hit = true;
						
						//We have hit the terrain so we dont need to loop anymore	
						break;
					}
					
					//Move along the ray
					//dist += stepDistance;
					rayPos += stepDistance * rayDir;

					if ((rayPos.y < height) != belowsurface) {
						belowsurface = rayPos.y < height;
						stepDistance *= -.5;
					}
				}
				clip(hit-.5);
				return finalUV;
			} else {
				return uv;
			}
		}

        void surf (Input IN, inout SurfaceOutputStandard o) {


			float3 rayDir = normalize(IN.tangentViewDir);
			float2 albedoUV, normalUV;

			if (_ShareUVs) {
				albedoUV = normalUV = parralaxUV(IN.uv_MainTex, rayDir);
			} else {
				albedoUV = parralaxUV(IN.uv_MainTex, rayDir);
				normalUV = parralaxUV(IN.uv_NormalMap, rayDir);
			}

            fixed4 albedo = sampleTex2D(_MainTex, albedoUV) * _Color;
			fixed3 normal = UnpackNormal(sampleTex2D(_NormalMap, normalUV));
			// fixed3 normal = getNormalFromHeight(normalUV);

            o.Albedo = albedo.rgb;
            o.Metallic = _Metallic;
            o.Smoothness = _Smoothness;
            o.Alpha = albedo.a;
			o.Normal = normal;
        }
        ENDCG
    }
    FallBack "Diffuse"
}

#if defined(USE_TEXTURE_ARRAY)
uniform sampler2DArray u_DiffuseMap;
#else
uniform sampler2D u_DiffuseMap;
#endif
uniform vec4      u_Color;

varying vec2      var_Tex1;


void main()
{
#if defined(USE_TEXTURE_ARRAY)
	// Both layers hold the same pixels, so layer 0 serves either eye.
	gl_FragColor = texture(u_DiffuseMap, vec3(var_Tex1, 0.0)) * u_Color;
#else
	gl_FragColor = texture2D(u_DiffuseMap, var_Tex1) * u_Color;
#endif
}

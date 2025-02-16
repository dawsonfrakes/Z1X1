package main

import "core:sys/windows"
import gl "vendor:OpenGL"

when ODIN_OS == .Windows {
	opengl32: windows.HMODULE
	opengl_ctx: windows.HGLRC

	opengl_platform_init :: proc "contextless" () {
		using windows

		pfd: PIXELFORMATDESCRIPTOR
		pfd.nSize = size_of(PIXELFORMATDESCRIPTOR)
		pfd.nVersion = 1
		pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER | PFD_DEPTH_DONTCARE
		pfd.cColorBits = 24
		format := ChoosePixelFormat(platform_hdc, &pfd)
		SetPixelFormat(platform_hdc, format, &pfd)

		temp_ctx := wglCreateContext(platform_hdc)
		defer wglDeleteContext(temp_ctx)
		wglMakeCurrent(platform_hdc, temp_ctx)

		wglCreateContextAttribsARB = auto_cast wglGetProcAddress("wglCreateContextAttribsARB")

		@static attribs := [?]i32{
			WGL_CONTEXT_MAJOR_VERSION_ARB, 4,
			WGL_CONTEXT_MINOR_VERSION_ARB, 6,
			WGL_CONTEXT_FLAGS_ARB, WGL_CONTEXT_DEBUG_BIT_ARB,
			WGL_CONTEXT_PROFILE_MASK_ARB, WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
			0,
		}

		opengl_ctx = wglCreateContextAttribsARB(platform_hdc, nil, raw_data(attribs[:]))
		wglMakeCurrent(platform_hdc, opengl_ctx)

		opengl32_name :: []u16{'o', 'p', 'e', 'n', 'g', 'l', '3', '2', 0}
		opengl32 = LoadLibraryW(raw_data(opengl32_name))

		load_legacy :: proc(p: rawptr, name: cstring) {
			(cast(^proc()) p)^ = auto_cast GetProcAddress(opengl32, name)
		}

		load_modern :: proc(p: rawptr, name: cstring) {
			(cast(^proc()) p)^ = auto_cast wglGetProcAddress(name)
		}

		context = {}
		gl.load_1_0(load_legacy)
		gl.load_1_1(load_legacy)
		gl.load_2_0(load_modern)
		gl.load_3_0(load_modern)
		gl.load_4_2(load_modern)
		gl.load_4_5(load_modern)
	}

	opengl_platform_deinit :: proc "contextless" () {
		using windows

		wglDeleteContext(opengl_ctx)
	}

	opengl_platform_present :: proc "contextless" () {
		using windows

		SwapBuffers(platform_hdc)
	}
} else {
	opengl_platform_init :: proc "contextless" () {}
	opengl_platform_deinit :: proc "contextless" () {}
	opengl_platform_present :: proc "contextless" () {}
}

OpenGLRectElement :: u8
OpenGLRectVertex :: struct {
	position: [2]f32,
}
OpenGLRectInstance :: struct {
	offset: [2]f32,
}

opengl_rect_vertices :: []OpenGLRectVertex{
	{position = {-0.5, -0.5}},
	{position = {+0.5, -0.5}},
	{position = {+0.5, +0.5}},
	{position = {-0.5, +0.5}},
}
opengl_rect_elements :: []OpenGLRectElement{
	0, 1, 2, 2, 3, 0,
}

opengl_main_fbo: u32
opengl_main_fbo_color0: u32
opengl_main_fbo_depth: u32

opengl_rect_shader: u32
opengl_rect_vao: u32
opengl_rect_vbo: u32
opengl_rect_ebo: u32
opengl_rect_ibo: u32

opengl_init :: proc "contextless" () {
	opengl_platform_init()

	gl.Enable(gl.FRAMEBUFFER_SRGB)
	gl.CreateFramebuffers(1, &opengl_main_fbo)
	gl.CreateRenderbuffers(1, &opengl_main_fbo_color0)
	gl.CreateRenderbuffers(1, &opengl_main_fbo_depth)

	{
		vshader := gl.CreateShader(gl.VERTEX_SHADER)
		defer gl.DeleteShader(vshader)
		vsrc : cstring = `#version 450

		layout(location = 0) in vec3 a_position;

		void main() {
			gl_Position = vec4(a_position, 1.0);
		}`
		vsrcs := []cstring{vsrc}
		gl.ShaderSource(vshader, cast(i32) len(vsrcs), raw_data(vsrcs), nil)
		gl.CompileShader(vshader)

		fshader := gl.CreateShader(gl.FRAGMENT_SHADER)
		defer gl.DeleteShader(fshader)
		fsrc : cstring = `#version 450

		layout(location = 0) out vec4 color;

		void main() {
			color = vec4(1.0, 0.0, 1.0, 1.0);
		}`
		fsrcs := []cstring{fsrc}
		gl.ShaderSource(fshader, cast(i32) len(fsrcs), raw_data(fsrcs), nil)
		gl.CompileShader(fshader)

		opengl_rect_shader = gl.CreateProgram()
		gl.AttachShader(opengl_rect_shader, vshader)
		gl.AttachShader(opengl_rect_shader, fshader)
		gl.LinkProgram(opengl_rect_shader)
		gl.DetachShader(opengl_rect_shader, fshader)
		gl.DetachShader(opengl_rect_shader, vshader)
	}

	{
		gl.CreateBuffers(1, &opengl_rect_vbo)
		gl.NamedBufferData(opengl_rect_vbo, len(opengl_rect_vertices) * size_of(OpenGLRectVertex), raw_data(opengl_rect_vertices), gl.STATIC_DRAW)
		gl.CreateBuffers(1, &opengl_rect_ebo)
		gl.NamedBufferData(opengl_rect_ebo, len(opengl_rect_elements) * size_of(OpenGLRectElement), raw_data(opengl_rect_elements), gl.STATIC_DRAW)
		gl.CreateBuffers(1, &opengl_rect_ibo)

		vbo_binding :: 0
		ibo_binding :: 1
		gl.CreateVertexArrays(1, &opengl_rect_vao)
		gl.VertexArrayVertexBuffer(opengl_rect_vao, vbo_binding, opengl_rect_vbo, 0, size_of(OpenGLRectVertex))
		gl.VertexArrayVertexBuffer(opengl_rect_vao, ibo_binding, opengl_rect_ibo, 0, size_of(OpenGLRectInstance))
		gl.VertexArrayBindingDivisor(opengl_rect_vao, ibo_binding, 1)
		gl.VertexArrayElementBuffer(opengl_rect_vao, opengl_rect_ebo)

		position_attrib :: 0
		gl.EnableVertexArrayAttrib(opengl_rect_vao, position_attrib)
		gl.VertexArrayAttribBinding(opengl_rect_vao, position_attrib, vbo_binding)
		gl.VertexArrayAttribFormat(opengl_rect_vao, position_attrib, 2, gl.FLOAT, false, cast(u32) offset_of(OpenGLRectVertex, position))
	}
}

opengl_deinit :: proc "contextless" () {
	opengl_platform_deinit()
}

opengl_resize :: proc "contextless" () {
	w := cast(i32) platform_width
	h := cast(i32) platform_height

	if w <= 0 || h <= 0 do return

	fbo_color_samples_max: i32 = ---
	gl.GetIntegerv(gl.MAX_COLOR_TEXTURE_SAMPLES, &fbo_color_samples_max)
	fbo_depth_samples_max: i32 = ---
	gl.GetIntegerv(gl.MAX_DEPTH_TEXTURE_SAMPLES, &fbo_depth_samples_max)
	fbo_samples := min(fbo_color_samples_max, fbo_depth_samples_max)

	gl.NamedRenderbufferStorageMultisample(opengl_main_fbo_color0, fbo_samples, gl.RGBA16F, w, h)
	gl.NamedFramebufferRenderbuffer(opengl_main_fbo, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, opengl_main_fbo_color0)

	gl.NamedRenderbufferStorageMultisample(opengl_main_fbo_depth, fbo_samples, gl.DEPTH_COMPONENT32F, w, h)
	gl.NamedFramebufferRenderbuffer(opengl_main_fbo, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, opengl_main_fbo_depth)
}

opengl_present :: proc "contextless" () {
	w := cast(i32) platform_width
	h := cast(i32) platform_height

	if w <= 0 || h <= 0 do return

	gl.Viewport(0, 0, w, h)

	gl.ClearNamedFramebufferfv(opengl_main_fbo, gl.COLOR, 0, raw_data([]f32{0.6, 0.2, 0.2, 1.0}))
	gl.ClearNamedFramebufferfv(opengl_main_fbo, gl.DEPTH, 0, raw_data([]f32{0.0}))

	gl.BindFramebuffer(gl.FRAMEBUFFER, opengl_main_fbo)

	gl.UseProgram(opengl_rect_shader)
	gl.BindVertexArray(opengl_rect_vao)
	gl.DrawElementsInstancedBaseVertexBaseInstance(gl.TRIANGLES, cast(i32) len(opengl_rect_elements), gl.UNSIGNED_BYTE, nil, 1, 0, 0)

	gl.BlitNamedFramebuffer(opengl_main_fbo, 0,
		0, 0, w, h,
		0, 0, w, h,
		gl.COLOR_BUFFER_BIT, gl.NEAREST)
	opengl_platform_present()
}

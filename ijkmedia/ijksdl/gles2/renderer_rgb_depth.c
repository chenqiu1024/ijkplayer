/*
 * Copyright (c) 2016 Bilibili
 * copyright (c) 2016 Zhang Rui <bbcallen@gmail.com>
 *
 * This file is part of ijkPlayer.
 *
 * ijkPlayer is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * ijkPlayer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with ijkPlayer; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#include "internal.h"

static GLboolean rgb_depth_use(IJK_GLES2_Renderer *renderer)
{
    ALOGI("use render rgb_depth\n");
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

    glUseProgram(renderer->program);            IJK_GLES2_checkError_TRACE("glUseProgram");

    if (0 == renderer->plane_textures[0])
        glGenTextures(1, renderer->plane_textures);

    for (int i = 0; i < 1; ++i) {
        glActiveTexture(GL_TEXTURE0 + i);
        glBindTexture(GL_TEXTURE_2D, renderer->plane_textures[i]);

        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

        glUniform1i(renderer->us2_sampler[i], i);
    }
    
    if (0 == renderer->depth_texture)
    {
        glGenTextures(1, &renderer->depth_texture);
    }
    glActiveTexture(GL_TEXTURE3);
    glBindTexture(GL_TEXTURE_2D, renderer->depth_texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glUniform1i(renderer->us2_depth, 3);

    return GL_TRUE;
}

static GLsizei rgb565_depth_getBufferWidth(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!overlay)
        return 0;

    return overlay->pitches[0] / 2;
}

static GLubyte* rgb565_depth_getLuminanceDataPointer(GLsizei* outWidth, GLsizei* outHeight, GLsizei* outLength, bool* outIsCopied, SDL_VoutOverlay* overlay) {
    if (!overlay)
        return NULL;
    
    if (outWidth) *outWidth = overlay->pitches[0] / 2;
    if (outHeight) *outHeight = overlay->h;
    if (outLength) *outLength = overlay->pitches[0] * overlay->h;
    if (outIsCopied) *outIsCopied = false;
    
    return overlay->pixels[0];
}

static GLboolean rgb565_depth_uploadTexture(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!renderer || !overlay)
        return GL_FALSE;

    int     planes[1]    = { 0 };
    const GLsizei widths[1]    = { overlay->pitches[0] / 2 };
    const GLsizei heights[3]   = { overlay->h };
    const GLubyte *pixels[3]   = { overlay->pixels[0] };

    switch (overlay->format) {
        case SDL_FCC_RV16:
            break;
        default:
            ALOGE("[rgb565] unexpected format %x\n", overlay->format);
            return GL_FALSE;
    }

    for (int i = 0; i < 1; ++i) {
        int plane = planes[i];

        glBindTexture(GL_TEXTURE_2D, renderer->plane_textures[i]);

        glTexImage2D(GL_TEXTURE_2D,
                     0,
                     GL_RGB,
                     widths[plane],
                     heights[plane],
                     0,
                     GL_RGB,
                     GL_UNSIGNED_SHORT_5_6_5,
                     pixels[plane]);
    }

    glBindTexture(GL_TEXTURE_2D, renderer->depth_texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, widths[0], heights[0], 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, pixels[0]);

    return GL_TRUE;
}

IJK_GLES2_Renderer *IJK_GLES2_Renderer_create_rgb565_depth()
{
    ALOGI("create render rgb565_depth\n");
    IJK_GLES2_Renderer *renderer = IJK_GLES2_Renderer_create_base(IJK_GLES2_getFragmentShader_rgb_depth());
    if (!renderer)
        goto fail;

    renderer->us2_sampler[0] = glGetUniformLocation(renderer->program, "us2_SamplerX"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_SamplerX)");

    renderer->us2_depth = glGetUniformLocation(renderer->program, "us2_Depth"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_Depth)");
    
    renderer->func_use            = rgb_depth_use;
    renderer->func_getBufferWidth = rgb565_depth_getBufferWidth;
    renderer->func_uploadTexture  = rgb565_depth_uploadTexture;
    renderer->func_getLuminanceDataPointer = rgb565_depth_getLuminanceDataPointer;

    return renderer;
fail:
    IJK_GLES2_Renderer_free(renderer);
    return NULL;
}



static GLsizei rgb888_depth_getBufferWidth(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!overlay)
        return 0;

    return overlay->pitches[0] / 3;
}

static GLubyte* rgb888_depth_getLuminanceDataPointer(GLsizei* outWidth, GLsizei* outHeight, GLsizei* outLength, bool* outIsCopied, SDL_VoutOverlay* overlay) {
    if (!overlay)
        return NULL;
    
    if (outWidth) *outWidth = overlay->pitches[0] / 3;
    if (outHeight) *outHeight = overlay->h;
    if (outLength) *outLength = overlay->pitches[0] * overlay->h;
    if (outIsCopied) *outIsCopied = false;
    
    return overlay->pixels[0];
}

static GLboolean rgb888_depth_uploadTexture(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!renderer || !overlay)
        return GL_FALSE;

    int     planes[1]    = { 0 };
    const GLsizei widths[1]    = { overlay->pitches[0] / 3 };
    const GLsizei heights[3]   = { overlay->h };
    const GLubyte *pixels[3]   = { overlay->pixels[0] };

    switch (overlay->format) {
        case SDL_FCC_RV24:
            break;
        default:
            ALOGE("[rgb888_depth] unexpected format %x\n", overlay->format);
            return GL_FALSE;
    }

    for (int i = 0; i < 1; ++i) {
        int plane = planes[i];

        glBindTexture(GL_TEXTURE_2D, renderer->plane_textures[i]);

        glTexImage2D(GL_TEXTURE_2D,
                     0,
                     GL_RGB,
                     widths[plane],
                     heights[plane],
                     0,
                     GL_RGB,
                     GL_UNSIGNED_BYTE,
                     pixels[plane]);
    }

    glBindTexture(GL_TEXTURE_2D, renderer->depth_texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, widths[0], heights[0], 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, pixels[0]);

    return GL_TRUE;
}

IJK_GLES2_Renderer *IJK_GLES2_Renderer_create_rgb888_depth()
{
    ALOGI("create render rgb888_depth\n");
    IJK_GLES2_Renderer *renderer = IJK_GLES2_Renderer_create_base(IJK_GLES2_getFragmentShader_rgb_depth());
    if (!renderer)
        goto fail;

    renderer->us2_sampler[0] = glGetUniformLocation(renderer->program, "us2_SamplerX"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_SamplerX)");

    renderer->us2_depth = glGetUniformLocation(renderer->program, "us2_Depth"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_Depth)");
    
    renderer->func_use            = rgb_depth_use;
    renderer->func_getBufferWidth = rgb888_depth_getBufferWidth;
    renderer->func_uploadTexture  = rgb888_depth_uploadTexture;
    renderer->func_getLuminanceDataPointer = rgb888_depth_getLuminanceDataPointer;

    return renderer;
fail:
    IJK_GLES2_Renderer_free(renderer);
    return NULL;
}



static GLsizei rgbx8888_depth_getBufferWidth(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!overlay)
        return 0;

    return overlay->pitches[0] / 4;
}

static GLubyte* rgbx8888_depth_getLuminanceDataPointer(GLsizei* outWidth, GLsizei* outHeight, GLsizei* outLength, bool* outIsCopied, SDL_VoutOverlay* overlay) {
    if (!overlay)
        return NULL;
    
    if (outWidth) *outWidth = overlay->pitches[0] / 4;
    if (outHeight) *outHeight = overlay->h;
    if (outLength) *outLength = overlay->pitches[0] * overlay->h;
    if (outIsCopied) *outIsCopied = false;
    
    return overlay->pixels[0];
}

static GLboolean rgbx8888_depth_uploadTexture(IJK_GLES2_Renderer *renderer, SDL_VoutOverlay *overlay)
{
    if (!renderer || !overlay)
        return GL_FALSE;

          int     planes[1]    = { 0 };
    const GLsizei widths[1]    = { overlay->pitches[0] / 4 };
    const GLsizei heights[3]   = { overlay->h };
    const GLubyte *pixels[3]   = { overlay->pixels[0] };

    switch (overlay->format) {
        case SDL_FCC_RV32:
            break;
        default:
            ALOGE("[rgbx8888] unexpected format %x\n", overlay->format);
            return GL_FALSE;
    }

    for (int i = 0; i < 1; ++i) {
        int plane = planes[i];

        glBindTexture(GL_TEXTURE_2D, renderer->plane_textures[i]);

        glTexImage2D(GL_TEXTURE_2D,
                     0,
                     GL_RGBA,
                     widths[plane],
                     heights[plane],
                     0,
                     GL_RGBA,
                     GL_UNSIGNED_BYTE,
                     pixels[plane]);
    }

    glBindTexture(GL_TEXTURE_2D, renderer->depth_texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, widths[0], heights[0], 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, pixels[0]);

    return GL_TRUE;
}

IJK_GLES2_Renderer *IJK_GLES2_Renderer_create_rgbx8888_depth()
{
    ALOGI("create render rgbx8888_depth\n");
    IJK_GLES2_Renderer *renderer = IJK_GLES2_Renderer_create_base(IJK_GLES2_getFragmentShader_rgb_depth());
    if (!renderer)
        goto fail;

    renderer->us2_sampler[0] = glGetUniformLocation(renderer->program, "us2_SamplerX"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_SamplerX)");

    renderer->us2_depth = glGetUniformLocation(renderer->program, "us2_Depth"); IJK_GLES2_checkError_TRACE("glGetUniformLocation(us2_Depth)");
    
    renderer->func_use            = rgb_depth_use;
    renderer->func_getBufferWidth = rgbx8888_depth_getBufferWidth;
    renderer->func_uploadTexture  = rgbx8888_depth_uploadTexture;
    renderer->func_getLuminanceDataPointer = rgbx8888_depth_getLuminanceDataPointer;

    return renderer;
fail:
    IJK_GLES2_Renderer_free(renderer);
    return NULL;
}

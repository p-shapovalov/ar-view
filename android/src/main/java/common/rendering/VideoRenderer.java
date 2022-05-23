///*
// * Copyright 2017 Google Inc. All Rights Reserved.
// * Licensed under the Apache License, Version 2.0 (the "License");
// * you may not use this file except in compliance with the License.
// * You may obtain a copy of the License at
// *
// *   http://www.apache.org/licenses/LICENSE-2.0
// *
// * Unless required by applicable law or agreed to in writing, software
// * distributed under the License is distributed on an "AS IS" BASIS,
// * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// * See the License for the specific language governing permissions and
// * limitations under the License.
// */
//package common.rendering;
//
//import android.graphics.SurfaceTexture;
//import android.opengl.GLES20;
//import android.opengl.Matrix;
//
//import java.io.IOException;
//import java.nio.FloatBuffer;
//import java.util.logging.Handler;
//
//public class VideoRenderer {
//    private SurfaceTexture videoTexture;
//    private int mTextureId;
//    private static final int TEXCOORDS_PER_VERTEX = 2;
//    private static final int COORDS_PER_VERTEX = 3;
//
//
//    private String TAG = VideoRenderer.class.getSimpleName();
//    private int mQuadProgram;
//    private final Object lock = new Object();
//
//    private static final String VERTEX_SHADER =
//            "uniform mat4 u_ModelViewProjection;\n\n" +
//                    "attribute vec4 a_Position;\n" +
//                    "attribute vec2 a_TexCoord;\n\n" +
//                    "varying vec2 v_TexCoord;\n\n" +
//                    "void main() {\n" +
//                    "   gl_Position = u_ModelViewProjection * vec4(a_Position.xyz, 1.0);\n" +
//                    "   v_TexCoord = a_TexCoord;\n" +
//                    "}";
//    private static final String FRAGMENT_SHADER =
//            "#extension GL_OES_EGL_image_external : require\n" +
//                    "\n" +
//                    "precision mediump float;\n" +
//                    "varying vec2 v_TexCoord;\n" +
//                    "uniform samplerExternalOES sTexture;\n" +
//                    "\n" +
//                    "void main() {\n" +
//                    "  vec4 input_color = texture2D(sTexture, v_TexCoord).rgba;\n" +
//                    "  gl_FragColor = input_color;\n" +
//                    "}";
//
//    private static final float[] QUAD_COORDS = new float[]{
//            -1.0f, -1.0f, 0.0f,
//            -1.0f, +1.0f, 0.0f,
//            +1.0f, -1.0f, 0.0f,
//            +1.0f, +1.0f, 0.0f,
//    };
//    private static final float[] QUAD_TEXCOORDS = new float[]{
//            0.0f, 0.0f,
//            0.0f, 1.0f,
//            1.0f, 0.0f,
//            1.0f, 1.0f
//    };
//    private final float[] modelViewProjection = new float[16];
//    private final float[] modelView = new float[16];
//
//    private static final int FLOAT_SIZE = 4;
//
//    private FloatBuffer mQuadVertices;
//
//    private final float[] mModelMatrix = new float[16];
//    private boolean frameAvailable;
//    private float[][] mTexCoordTransformationMatrix;
//    private int mQuadPositionParam;
//    private int mQuadTexCoordParam;
//    private int mModelViewProjectionUniform;
//    private final float[] VIDEO_QUAD_TEXTCOORDS_TRANSFORMED = new float[]{0.0f, 0.0f,
//            1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f,};
//
//    public void createOnGlThread() {
//
//        // 1 texture to hold the video frame.
//        int textures[] = new int[1];
//        GLES20.glGenTextures(1, textures, 0);
//        mTextureId = textures[0];
//        int mTextureTarget = GLES11Ext.GL_TEXTURE_EXTERNAL_OES;
//        GLES20.glBindTexture(mTextureTarget, mTextureId);
//
//        GLES20.glTexParameteri(mTextureTarget, GLES20.GL_TEXTURE_MIN_FILTER,
//                GLES20.GL_NEAREST);
//        GLES20.glTexParameteri(mTextureTarget, GLES20.GL_TEXTURE_MAG_FILTER,
//                GLES20.GL_NEAREST);
//
//        mTexCoordTransformationMatrix = new float[1][16];
//
//        createQuardCoord();
//        createQuadTextCoord();
//        int vertexShader = loadGLShader(GLES20.GL_VERTEX_SHADER, VERTEX_SHADER);
//        int fragmentShader = loadGLShader(
//                GLES20.GL_FRAGMENT_SHADER, FRAGMENT_SHADER);
//
//        mQuadProgram = GLES20.glCreateProgram();
//        GLES20.glAttachShader(mQuadProgram, vertexShader);
//        GLES20.glAttachShader(mQuadProgram, fragmentShader);
//        GLES20.glLinkProgram(mQuadProgram);
//        GLES20.glUseProgram(mQuadProgram);
//
//
//        ShaderUtil.checkGLError(TAG, "Program creation");
//
//        mQuadPositionParam = GLES20.glGetAttribLocation(mQuadProgram, "a_Position");
//        mQuadTexCoordParam = GLES20.glGetAttribLocation(mQuadProgram, "a_TexCoord");
//        mModelViewProjectionUniform = GLES20.glGetUniformLocation(
//                mQuadProgram, "u_ModelViewProjection");
//
//        ShaderUtil.checkGLError(TAG, "Program parameters");
//        Matrix.setIdentityM(mModelMatrix, 0);
//
//        initializeMediaPlayer();
//    }
//
//
//    public void update(float[] modelMatrix) {
//        float[] scaleMatrix = new float[16];
//        Matrix.setIdentityM(scaleMatrix, 0);
//        float SCALE_FACTOR = 1f;
//        scaleMatrix[0] = SCALE_FACTOR;
//        scaleMatrix[5] = SCALE_FACTOR;
//        scaleMatrix[10] = SCALE_FACTOR;
//        Matrix.multiplyMM(this.mModelMatrix, 0, modelMatrix, 0, scaleMatrix, 0);
//    }
//
//    public void draw(float[] cameraView, float[] cameraPerspective) {
//        if (done || !prepared) {
//            return;
//        }
//        synchronized (this) {
//            if (frameAvailable) {
//                videoTexture.updateTexImage();
//                frameAvailable = false;
//
//                if (videoTexture != null) {
//                    videoTexture.getTransformMatrix(mTexCoordTransformationMatrix[0]);
//                    setVideoDimensions(mTexCoordTransformationMatrix[0]);
//                    createQuadTextCoord();
//                }
//            }
//        }
//        Matrix.multiplyMM(modelView, 0, cameraView, 0, mModelMatrix, 0);
//        Matrix.multiplyMM(modelViewProjection, 0, cameraPerspective, 0, modelView, 0);
//
//        // ShaderUtil.checkGLError(TAG, "Before draw");
//
//        GLES20.glEnable(GL10.GL_BLEND);
//        GLES20.glBlendFunc(GL10.GL_SRC_ALPHA, GL10.GL_ONE_MINUS_SRC_ALPHA);
//        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, mTextureId);
//        GLES20.glUseProgram(mQuadProgram);
//
//
//        // Set the vertex positions.
//        GLES20.glVertexAttribPointer(mQuadPositionParam, COORDS_PER_VERTEX,
//                GLES20.GL_FLOAT, false, 0, mQuadVertices);
//
//        // Set the texture coordinates.
//        GLES20.glVertexAttribPointer(mQuadTexCoordParam, TEXCOORDS_PER_VERTEX,
//                GLES20.GL_FLOAT, false, 0, fillBuffer(VIDEO_QUAD_TEXTCOORDS_TRANSFORMED));
//
//        // Enable vertex arrays
//        GLES20.glEnableVertexAttribArray(mQuadPositionParam);
//        GLES20.glEnableVertexAttribArray(mQuadTexCoordParam);
//        GLES20.glUniformMatrix4fv(mModelViewProjectionUniform, 1, false,
//                modelViewProjection, 0);
//
//        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4);
//
//        // Disable vertex arrays
//        GLES20.glDisableVertexAttribArray(mQuadPositionParam);
//        GLES20.glDisableVertexAttribArray(mQuadTexCoordParam);
//
//        ShaderUtil.checkGLError(TAG, "Draw");
//    }
//
//    private void setVideoDimensions(float[] textureCoordMatrix) {
//        float tempUVMultRes[];
//
//        tempUVMultRes = uvMultMat4f(QUAD_TEXCOORDS[0], QUAD_TEXCOORDS[1], textureCoordMatrix);
//        VIDEO_QUAD_TEXTCOORDS_TRANSFORMED[0] = tempUVMultRes[0];
//        VIDEO_QUAD_TEXTCOORDS_TRANSFORMED[1] = tempUVMultRes[1];
//        tempUVMultRes = uvMultMat4f(QUAD_TEXCOORDS[2], QUAD_TEXCOORDS[3], textureCoordMatrix);
//        VIDEO_QUAD_TEXTCOORDS_TRANSFORMED[2] = tempUVMultRes[0];
//        VIDEO_QUAD_TEXTCOORDS_TRANSFORMED[3] = tempUVMultRes[1];
//        tempUVMultRes = uvMultMat4f(QUAD_TEXCOORDS[4], QUAD_TEXCOORDS[5], textureCoordMatrix);
//        VIDEO_QUAD_TEXTCOORDS_TRANSFORMED[4] = tempUVMultRes[0];
//        VIDEO_QUAD_TEXTCOORDS_TRANSFORMED[5] = tempUVMultRes[1];
//        tempUVMultRes = uvMultMat4f(QUAD_TEXCOORDS[6], QUAD_TEXCOORDS[7], textureCoordMatrix);
//        VIDEO_QUAD_TEXTCOORDS_TRANSFORMED[6] = tempUVMultRes[0];
//        VIDEO_QUAD_TEXTCOORDS_TRANSFORMED[7] = tempUVMultRes[1];
//    }
//
//    private void createQuadTextCoord() {
//        int numVertices = 4;
//        ByteBuffer bbTexCoords = ByteBuffer.allocateDirect(
//                numVertices * TEXCOORDS_PER_VERTEX * FLOAT_SIZE);
//        bbTexCoords.order(ByteOrder.nativeOrder());
//        FloatBuffer mQuadTexCoord = bbTexCoords.asFloatBuffer();
//        mQuadTexCoord.put(QUAD_TEXCOORDS);
//        mQuadTexCoord.position(0);
//    }
//
//    // Make a quad to hold the movie
//    private void createQuardCoord() {
//        ByteBuffer bbVertices = ByteBuffer.allocateDirect(
//                QUAD_COORDS.length * FLOAT_SIZE);
//        bbVertices.order(ByteOrder.nativeOrder());
//        mQuadVertices = bbVertices.asFloatBuffer();
//        mQuadVertices.put(QUAD_COORDS);
//        mQuadVertices.position(0);
//    }
//
//    private Buffer fillBuffer(float[] array) {
//        // Convert to floats because OpenGL doesnt work on doubles, and manually
//        // casting each input value would take too much time.
//        ByteBuffer bb = ByteBuffer.allocateDirect(4 * array.length); // each float takes 4 bytes
//        bb.order(ByteOrder.LITTLE_ENDIAN);
//        for (float d : array)
//            bb.putFloat(d);
//        bb.rewind();
//
//        return bb;
//
//    }
//
//    private float[] uvMultMat4f(float u,
//                                float v, float[] pMat) {
//        float x = pMat[0] * u + pMat[4] * v + pMat[12]
//                * 1.f;
//        float y = pMat[1] * u + pMat[5] * v + pMat[13]
//                * 1.f;
//
//        float result[] = new float[2];
//        result[0] = x;
//        result[1] = y;
//        return result;
//    }
//
//    public boolean isStarted() {
//        return started;
//    }
//
//    private static int loadGLShader(int glVertexShader, String vertexShader) {
//        int shader = GLES20.glCreateShader(glVertexShader);
//        GLES20.glShaderSource(shader, vertexShader);
//        GLES20.glCompileShader(shader);
//
//        final int[] status = new int[1];
//        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0);
//
//        if (status[0] == 0) {
//            Log.e("SHADER", "Error in compiling shader: " + GLES20.glGetShaderInfoLog(shader));
//            GLES20.glDeleteShader(shader);
//            shader = 0;
//        }
//
//        if (shader == 0) {
//            throw new RuntimeException("Error creating shader.");
//        }
//
//        return shader;
//    }
//}
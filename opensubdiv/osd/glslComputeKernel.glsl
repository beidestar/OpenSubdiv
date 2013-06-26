//
//     Copyright (C) Pixar. All rights reserved.
//
//     This license governs use of the accompanying software. If you
//     use the software, you accept this license. If you do not accept
//     the license, do not use the software.
//
//     1. Definitions
//     The terms "reproduce," "reproduction," "derivative works," and
//     "distribution" have the same meaning here as under U.S.
//     copyright law.  A "contribution" is the original software, or
//     any additions or changes to the software.
//     A "contributor" is any person or entity that distributes its
//     contribution under this license.
//     "Licensed patents" are a contributor's patent claims that read
//     directly on its contribution.
//
//     2. Grant of Rights
//     (A) Copyright Grant- Subject to the terms of this license,
//     including the license conditions and limitations in section 3,
//     each contributor grants you a non-exclusive, worldwide,
//     royalty-free copyright license to reproduce its contribution,
//     prepare derivative works of its contribution, and distribute
//     its contribution or any derivative works that you create.
//     (B) Patent Grant- Subject to the terms of this license,
//     including the license conditions and limitations in section 3,
//     each contributor grants you a non-exclusive, worldwide,
//     royalty-free license under its licensed patents to make, have
//     made, use, sell, offer for sale, import, and/or otherwise
//     dispose of its contribution in the software or derivative works
//     of the contribution in the software.
//
//     3. Conditions and Limitations
//     (A) No Trademark License- This license does not grant you
//     rights to use any contributor's name, logo, or trademarks.
//     (B) If you bring a patent claim against any contributor over
//     patents that you claim are infringed by the software, your
//     patent license from such contributor to the software ends
//     automatically.
//     (C) If you distribute any portion of the software, you must
//     retain all copyright, patent, trademark, and attribution
//     notices that are present in the software.
//     (D) If you distribute any portion of the software in source
//     code form, you may do so only under this license by including a
//     complete copy of this license with your distribution. If you
//     distribute any portion of the software in compiled or object
//     code form, you may only do so under a license that complies
//     with this license.
//     (E) The software is licensed "as-is." You bear the risk of
//     using it. The contributors give no express warranties,
//     guarantees or conditions. You may have additional consumer
//     rights under your local laws which this license cannot change.
//     To the extent permitted under your local laws, the contributors
//     exclude the implied warranties of merchantability, fitness for
//     a particular purpose and non-infringement.
//
#version 430

subroutine void computeKernelType();
subroutine uniform computeKernelType computeKernel;

uniform int vertexOffset = 0;   // vertex index offset for the batch
uniform int tableOffset = 0;    // offset of subdivision table
uniform int indexStart = 0;     // start index relative to tableOffset
uniform int indexEnd = 0;       // end index relative to tableOffset
uniform bool vertexPass;

/*
 +-----+---------------------------------+-----
   n-1 |   Level n   |<batch range>|     |  n+1
 +-----+---------------------------------+-----
       ^             ^             ^
  vertexOffset       |             |
                 indexStart     indexEnd
*/

layout(binding=0) buffer vertex_buffer  { float vertexBuffer[]; };
layout(binding=1) buffer varying_buffer { float varyingBuffer[]; };
layout(binding=2) buffer _F0_IT         { int _F_IT[]; };
layout(binding=3) buffer _F0_ITa        { int _F_ITa[]; };
layout(binding=4) buffer _E0_IT         { int _E_IT[]; };
layout(binding=5) buffer _V0_IT         { int _V_IT[]; };
layout(binding=6) buffer _V0_ITa        { int _V_ITa[]; };
layout(binding=7) buffer _E0_S          { float _E_W[]; };
layout(binding=8) buffer _V0_S          { float _V_W[]; };
layout(binding=9) buffer _editIndices_buffer  { int _editIndices[]; };
layout(binding=10) buffer _editValues_buffer  { float _editValues[]; };
layout(local_size_x=WORK_GROUP_SIZE, local_size_y=1, local_size_z=1) in;

//--------------------------------------------------------------------------------

struct Vertex
{
#if NUM_VERTEX_ELEMENTS > 0
    float vertexData[NUM_VERTEX_ELEMENTS];
#endif
#if NUM_VARYING_ELEMENTS > 0
    float varyingData[NUM_VARYING_ELEMENTS];
#endif
};

void clear(out Vertex v)
{
#if NUM_VERTEX_ELEMENTS > 0
    for(int i = 0; i < NUM_VERTEX_ELEMENTS; i++) {
        v.vertexData[i] = 0;
    }
#endif
#if NUM_VARYING_ELEMENTS > 0
    for(int i = 0; i < NUM_VARYING_ELEMENTS; i++){
        v.varyingData[i] = 0;
    }
#endif
}

Vertex readVertex(int index)
{
    Vertex v;

#if NUM_VERTEX_ELEMENTS > 0
    for (int i = 0; i < NUM_VERTEX_ELEMENTS; i++) {
        v.vertexData[i] = vertexBuffer[index*NUM_VERTEX_ELEMENTS+i];
    }
#endif
#if NUM_VARYING_ELEMENTS > 0
    for (int i = 0; i < NUM_VARYING_ELEMENTS; i++) {
        v.varyingData[i] = varyingBuffer[index*NUM_VARYING_ELEMENTS+i];
    }
#endif
    return v;
}

void writeVertex(int index, Vertex v)
{
#if NUM_VERTEX_ELEMENTS > 0
    for (int i = 0; i < NUM_VERTEX_ELEMENTS; i++) {
        vertexBuffer[index*NUM_VERTEX_ELEMENTS+i] = v.vertexData[i];
    }
#endif
#if NUM_VARYING_ELEMENTS > 0
    for (int i = 0; i < NUM_VARYING_ELEMENTS; i++) {
        varyingBuffer[index*NUM_VARYING_ELEMENTS+i] = v.varyingData[i];
    }
#endif
}

void addWithWeight(inout Vertex v, Vertex src, float weight)
{
#if NUM_VERTEX_ELEMENTS > 0
    for (int i = 0; i < NUM_VERTEX_ELEMENTS; i++) {
        v.vertexData[i] += weight * src.vertexData[i];
    }
#endif
}

void addVaryingWithWeight(inout Vertex v, Vertex src, float weight)
{
#if NUM_VARYING_ELEMENTS > 0
    for (int i = 0; i < NUM_VARYING_ELEMENTS; i++) {
        v.varyingData[i] += weight * src.varyingData[i];
    }
#endif
}

//--------------------------------------------------------------------------------
// Face-vertices compute Kernel
subroutine(computeKernelType)
void catmarkComputeFace()
{
    int i = int(gl_GlobalInvocationID.x) + indexStart;
    if (i >= indexEnd) return;
    int vid = i + vertexOffset;
    i += tableOffset;

    int h = _F_ITa[2*i];
    int n = _F_ITa[2*i+1];

    float weight = 1.0/n;

    Vertex dst;
    clear(dst);
    for(int j=0; j<n; ++j){
        int index = _F_IT[h+j];
        addWithWeight(dst, readVertex(index), weight);
        addVaryingWithWeight(dst, readVertex(index), weight);
    }
    writeVertex(vid, dst);
}

// Edge-vertices compute Kernepl
subroutine(computeKernelType)
void catmarkComputeEdge()
{
    int i = int(gl_GlobalInvocationID.x) + indexStart;
    if (i >= indexEnd) return;
    int vid = i + vertexOffset;
    i += tableOffset;

    Vertex dst;
    clear(dst);

    int eidx0 = _E_IT[4*i+0];
    int eidx1 = _E_IT[4*i+1];
    int eidx2 = _E_IT[4*i+2];
    int eidx3 = _E_IT[4*i+3];
    ivec4 eidx = ivec4(eidx0, eidx1, eidx2, eidx3);

    float vertWeight = _E_W[i*2+0];

    // Fully sharp edge : vertWeight = 0.5f;
    addWithWeight(dst, readVertex(eidx.x), vertWeight);
    addWithWeight(dst, readVertex(eidx.y), vertWeight);

    if(eidx.z != -1){
        float faceWeight = _E_W[i*2+1];

        addWithWeight(dst, readVertex(eidx.z), faceWeight);
        addWithWeight(dst, readVertex(eidx.w), faceWeight);
    }

    addVaryingWithWeight(dst, readVertex(eidx.x), 0.5f);
    addVaryingWithWeight(dst, readVertex(eidx.y), 0.5f);

    writeVertex(vid, dst);
}

// Edge-vertices compute Kernel (bilinear scheme)
subroutine(computeKernelType)
void bilinearComputeEdge()
{
    int i = int(gl_GlobalInvocationID.x) + indexStart;
    if (i >= indexEnd) return;
    int vid = i + vertexOffset;
    i += tableOffset;

    Vertex dst;
    clear(dst);

    ivec2 eidx = ivec2(_E_IT[2*i+0],
                       _E_IT[2*i+1]);

    addWithWeight(dst, readVertex(eidx.x), 0.5f);
    addWithWeight(dst, readVertex(eidx.y), 0.5f);

    addVaryingWithWeight(dst, readVertex(eidx.x), 0.5f);
    addVaryingWithWeight(dst, readVertex(eidx.y), 0.5f);

    writeVertex(vid, dst);
}

// Vertex-vertices compute Kernel (bilinear scheme)
subroutine(computeKernelType)
void bilinearComputeVertex()
{
    int i = int(gl_GlobalInvocationID.x) + indexStart;
    if (i >= indexEnd) return;
    int vid = i + vertexOffset;
    i += tableOffset;

    Vertex dst;
    clear(dst);

    int p = _V_ITa[i];

    addWithWeight(dst, readVertex(p), 1.0f);

    addVaryingWithWeight(dst, readVertex(p), 1.0f);

    writeVertex(vid, dst);
}

// Vertex-vertices compute Kernels 'A' / k_Crease and k_Corner rules
subroutine(computeKernelType)
void catmarkComputeVertexA()
{
    int i = int(gl_GlobalInvocationID.x) + indexStart;
    if (i >= indexEnd) return;
    int vid = i + vertexOffset;
    i += tableOffset;

    int n     = _V_ITa[5*i+1];
    int p     = _V_ITa[5*i+2];
    int eidx0 = _V_ITa[5*i+3];
    int eidx1 = _V_ITa[5*i+4];

    float weight = vertexPass ? _V_W[i] : 1.0 - _V_W[i];

    // In the case of fractional weight, the weight must be inverted since
    // the value is shared with the k_Smooth kernel (statistically the
    // k_Smooth kernel runs much more often than this one)
    if (weight>0.0 && weight<1.0 && n > 0)
        weight=1.0-weight;

    Vertex dst;
    if(! vertexPass)
        clear(dst);
    else
        dst = readVertex(vid);

    if (eidx0==-1 || (vertexPass==false && (n==-1)) ) {
        addWithWeight(dst, readVertex(p), weight);
    } else {
        addWithWeight(dst, readVertex(p), weight * 0.75f);
        addWithWeight(dst, readVertex(eidx0), weight * 0.125f);
        addWithWeight(dst, readVertex(eidx1), weight * 0.125f);
    }
    if(! vertexPass)
        addVaryingWithWeight(dst, readVertex(p), 1);

    writeVertex(vid, dst);
}

// Vertex-vertices compute Kernels 'B' / k_Dart and k_Smooth rules
subroutine(computeKernelType)
void catmarkComputeVertexB()
{
    int i = int(gl_GlobalInvocationID.x) + indexStart;
    if (i >= indexEnd) return;
    int vid = i + vertexOffset;
    i += tableOffset;

    int h = _V_ITa[5*i];
    int n = _V_ITa[5*i+1];
    int p = _V_ITa[5*i+2];

    float weight = _V_W[i];
    float wp = 1.0/float(n*n);
    float wv = (n-2.0) * n * wp;

    Vertex dst;
    clear(dst);

    addWithWeight(dst, readVertex(p), weight * wv);

    for(int j = 0; j < n; ++j){
        addWithWeight(dst, readVertex(_V_IT[h+j*2]), weight * wp);
        addWithWeight(dst, readVertex(_V_IT[h+j*2+1]), weight * wp);
    }
    addVaryingWithWeight(dst, readVertex(p), 1);
    writeVertex(vid, dst);
}

// Vertex-vertices compute Kernels 'B' / k_Dart and k_Smooth rules
subroutine(computeKernelType)
void loopComputeVertexB()
{
    float PI = 3.14159265358979323846264;
    int i = int(gl_GlobalInvocationID.x) + indexStart;
    if (i >= indexEnd) return;
    int vid = i + vertexOffset;
    i += tableOffset;

    int h = _V_ITa[5*i];
    int n = _V_ITa[5*i+1];
    int p = _V_ITa[5*i+2];

    float weight = _V_W[i];
    float wp = 1.0/n;
    float beta = 0.25 * cos(PI*2.0f*wp)+0.375f;
    beta = beta * beta;
    beta = (0.625f-beta)*wp;

    Vertex dst;
    clear(dst);

    addWithWeight(dst, readVertex(p), weight * (1.0-(beta*n)));

    for(int j = 0; j < n; ++j){
        addWithWeight(dst, readVertex(_V_IT[h+j]), weight * beta);
    }
    addVaryingWithWeight(dst, readVertex(p), 1);
    writeVertex(vid, dst);
}

// vertex edit kernel
uniform int editPrimVarOffset;
uniform int editPrimVarWidth;

subroutine(computeKernelType)
void editAdd()
{
    int i = int(gl_GlobalInvocationID.x) + indexStart;
    if (i >= indexEnd) return;
    i += tableOffset;

    int v = _editIndices[i];
    Vertex dst = readVertex(v + vertexOffset);

    // seemingly we can't iterate dynamically over vertexData[n]
    // due to mysterious glsl runtime limitation...?
    for (int j = 0; j < NUM_VERTEX_ELEMENTS; ++j) {
        float editValue = _editValues[i*editPrimVarWidth + min(j, editPrimVarWidth)];
        editValue *= float(j >= editPrimVarOffset);
        editValue *= float(j < (editPrimVarWidth + editPrimVarOffset));
        dst.vertexData[j] += editValue;
    }
    writeVertex(v + vertexOffset, dst);
}

void main()
{
    // call subroutine
    computeKernel();
}

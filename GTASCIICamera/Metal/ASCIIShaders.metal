//
//  ASCIIShaders.metal
//  GT ASCII Camera
//
//  Created by Gennaro Eduardo Tangari on 27/02/2026.
//  Copyright © 2026 Gennaro Eduardo Tangari. All rights reserved.
//
//  Metal compute kernel that converts a camera frame into ASCII art.
//  Each thread processes one output pixel:
//    1. Determines which ASCII grid cell it belongs to.
//    2. Samples the source texture region for average luminance/color.
//    3. Maps luminance to a glyph index.
//    4. Looks up the glyph from a pre-rendered atlas.
//    5. Composites the glyph onto the output.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Uniforms

struct RenderUniforms {
    uint columns;
    uint rows;
    uint paletteSize;
    uint textureWidth;
    uint textureHeight;
    uint invertLuminance;
    float fontSize;
    float contrast;  // 1.0 = normal, higher values increase contrast
};

// MARK: - Colored ASCII Kernel

kernel void asciiArtKernel(
    texture2d<float, access::read>   sourceTexture   [[texture(0)]],
    texture2d<float, access::read>   glyphAtlas      [[texture(1)]],
    texture2d<float, access::write>  outputTexture   [[texture(2)]],
    constant RenderUniforms&         uniforms        [[buffer(0)]],
    uint2                            gid             [[thread_position_in_grid]]
) {
    uint outWidth  = outputTexture.get_width();
    uint outHeight = outputTexture.get_height();

    if (gid.x >= outWidth || gid.y >= outHeight) return;

    float cellW = float(outWidth)  / float(uniforms.columns);
    float cellH = float(outHeight) / float(uniforms.rows);

    uint cellX = min(uint(float(gid.x) / cellW), uniforms.columns - 1);
    uint cellY = min(uint(float(gid.y) / cellH), uniforms.rows - 1);

    // Source texture region for this cell
    float srcCellW = float(uniforms.textureWidth)  / float(uniforms.columns);
    float srcCellH = float(uniforms.textureHeight) / float(uniforms.rows);
    uint srcStartX = uint(float(cellX) * srcCellW);
    uint srcStartY = uint(float(cellY) * srcCellH);
    uint srcEndX   = min(uint(float(cellX + 1) * srcCellW), uniforms.textureWidth);
    uint srcEndY   = min(uint(float(cellY + 1) * srcCellH), uniforms.textureHeight);

    // Downsample: average luminance and color (up to 8×8 samples per cell)
    float totalLum = 0.0;
    float3 totalColor = float3(0.0);
    float sampleCount = 0.0;

    uint stepX = max(1u, (srcEndX - srcStartX) / 8u);
    uint stepY = max(1u, (srcEndY - srcStartY) / 8u);

    for (uint sy = srcStartY; sy < srcEndY; sy += stepY) {
        for (uint sx = srcStartX; sx < srcEndX; sx += stepX) {
            float4 pixel = sourceTexture.read(uint2(sx, sy));
            float lum = 0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b;
            totalLum += lum;
            totalColor += pixel.rgb;
            sampleCount += 1.0;
        }
    }

    float avgLum = (sampleCount > 0.0) ? totalLum / sampleCount : 0.0;
    float3 avgColor = (sampleCount > 0.0) ? totalColor / sampleCount : float3(0.0);

    // Apply contrast adjustment
    avgLum = saturate((avgLum - 0.5) * uniforms.contrast + 0.5);

    if (uniforms.invertLuminance != 0) {
        avgLum = 1.0 - avgLum;
    }

    // Map to glyph index
    uint glyphIndex = min(uint(avgLum * float(uniforms.paletteSize - 1) + 0.5),
                          uniforms.paletteSize - 1);

    // Atlas lookup
    uint atlasW = glyphAtlas.get_width();
    uint atlasH = glyphAtlas.get_height();
    float glyphW = float(atlasW) / float(uniforms.paletteSize);

    float localX = (float(gid.x) - float(cellX) * cellW) / cellW;
    float localY = (float(gid.y) - float(cellY) * cellH) / cellH;

    float atlasX = (float(glyphIndex) + localX) * glyphW;
    float atlasY = localY * float(atlasH);

    uint2 atlasCoord = uint2(min(uint(atlasX), atlasW - 1),
                              min(uint(atlasY), atlasH - 1));

    float4 glyphSample = glyphAtlas.read(atlasCoord);
    float alpha = glyphSample.a;

    // Boost saturation slightly
    float maxC = max(max(avgColor.r, avgColor.g), avgColor.b);
    float minC = min(min(avgColor.r, avgColor.g), avgColor.b);
    if (maxC - minC > 0.01) {
        float mid = (maxC + minC) * 0.5;
        avgColor = saturate(mix(float3(mid), avgColor, 1.3));
    }

    float3 bgColor = float3(0.0);
    float3 finalColor = mix(bgColor, avgColor, alpha);
    outputTexture.write(float4(finalColor, 1.0), gid);
}

// MARK: - Monochrome ASCII Kernel

kernel void asciiArtMonochromeKernel(
    texture2d<float, access::read>   sourceTexture   [[texture(0)]],
    texture2d<float, access::read>   glyphAtlas      [[texture(1)]],
    texture2d<float, access::write>  outputTexture   [[texture(2)]],
    constant RenderUniforms&         uniforms        [[buffer(0)]],
    constant float4&                 fgColorParam    [[buffer(1)]],
    constant float4&                 bgColorParam    [[buffer(2)]],
    uint2                            gid             [[thread_position_in_grid]]
) {
    uint outWidth  = outputTexture.get_width();
    uint outHeight = outputTexture.get_height();

    if (gid.x >= outWidth || gid.y >= outHeight) return;

    float cellW = float(outWidth)  / float(uniforms.columns);
    float cellH = float(outHeight) / float(uniforms.rows);

    uint cellX = min(uint(float(gid.x) / cellW), uniforms.columns - 1);
    uint cellY = min(uint(float(gid.y) / cellH), uniforms.rows - 1);

    float srcCellW = float(uniforms.textureWidth)  / float(uniforms.columns);
    float srcCellH = float(uniforms.textureHeight) / float(uniforms.rows);
    uint srcStartX = uint(float(cellX) * srcCellW);
    uint srcStartY = uint(float(cellY) * srcCellH);
    uint srcEndX   = min(uint(float(cellX + 1) * srcCellW), uniforms.textureWidth);
    uint srcEndY   = min(uint(float(cellY + 1) * srcCellH), uniforms.textureHeight);

    float totalLum = 0.0;
    float sampleCount = 0.0;
    uint stepX = max(1u, (srcEndX - srcStartX) / 8u);
    uint stepY = max(1u, (srcEndY - srcStartY) / 8u);

    for (uint sy = srcStartY; sy < srcEndY; sy += stepY) {
        for (uint sx = srcStartX; sx < srcEndX; sx += stepX) {
            float4 pixel = sourceTexture.read(uint2(sx, sy));
            totalLum += 0.2126 * pixel.r + 0.7152 * pixel.g + 0.0722 * pixel.b;
            sampleCount += 1.0;
        }
    }

    float avgLum = (sampleCount > 0.0) ? totalLum / sampleCount : 0.0;

    // Apply contrast adjustment
    avgLum = saturate((avgLum - 0.5) * uniforms.contrast + 0.5);

    if (uniforms.invertLuminance != 0) {
        avgLum = 1.0 - avgLum;
    }

    uint glyphIndex = min(uint(avgLum * float(uniforms.paletteSize - 1) + 0.5),
                          uniforms.paletteSize - 1);

    uint atlasW = glyphAtlas.get_width();
    uint atlasH = glyphAtlas.get_height();
    float glyphW = float(atlasW) / float(uniforms.paletteSize);

    float localX = (float(gid.x) - float(cellX) * cellW) / cellW;
    float localY = (float(gid.y) - float(cellY) * cellH) / cellH;

    float atlasX = (float(glyphIndex) + localX) * glyphW;
    float atlasY = localY * float(atlasH);

    uint2 atlasCoord = uint2(min(uint(atlasX), atlasW - 1),
                              min(uint(atlasY), atlasH - 1));

    float4 glyphSample = glyphAtlas.read(atlasCoord);
    float alpha = glyphSample.a;

    float3 finalColor = mix(bgColorParam.rgb, fgColorParam.rgb, alpha);
    outputTexture.write(float4(finalColor, 1.0), gid);
}

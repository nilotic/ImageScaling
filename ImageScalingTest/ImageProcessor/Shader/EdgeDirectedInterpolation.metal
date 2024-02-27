//
//  EdgeDirectedInterpolation.metal
//  ImageScalingTest
//
//  Created by Den Jo on 2/25/24.
//
#include <metal_stdlib>
using namespace metal;

typedef struct {
    float intensity;
    float2 direction;
} EdgeInfo;

constant int2 offsets[8] = {
    {-1, -1}, {0, -1}, {1, -1},
    {-1,  0},         {1,  0},
    {-1,  1}, {0,  1}, {1,  1}
};

kernel void edgeDirectedInterpolation(texture2d<float, access::read> inputTexture [[texture(0)]], texture2d<float, access::write> outputTexture [[texture(1)]], uint2 gid [[thread_position_in_grid]]) {
    int width = inputTexture.get_width();
    int height = inputTexture.get_height();
    int2 pos = int2(gid);
    
    if (pos.x >= width || pos.y >= height) return;
    
    float4 centerPixel = inputTexture.read(gid);
    EdgeInfo edgeInfo = {0.0, float2(0.0, 0.0)};
    float maxIntensity = 0.0;
    
    // 각 방향에 대해 경계 강도 계산
    for (int i = 0; i < 8; ++i) {
        int2 curOffset = offsets[i];
        uint2 checkPos = uint2(clamp(pos + curOffset, int2(0, 0), int2(width - 1, height - 1)));
        
        float4 neighborPixel = inputTexture.read(checkPos);
        float intensity = length(abs(centerPixel.rgb - neighborPixel.rgb));
        
        if (intensity > maxIntensity) {
            maxIntensity = intensity;
            edgeInfo.intensity = intensity;
            edgeInfo.direction = normalize(float2(curOffset));
        }
    }
    
    if (edgeInfo.intensity > 0.1) { // 경계 감지 임계값
        float2 perpendicularDirection = float2(-edgeInfo.direction.y, edgeInfo.direction.x);
        float4 interpolatedPixel = float4(0.0);
        float weightSum = 0.0;
        
        // 경계 방향에 수직인 방향의 두 주변 픽셀을 찾아서 보간합니다.
        for (int i = -1; i <= 1; i += 2) {
            float2 offset = float2(perpendicularDirection.x * i, perpendicularDirection.y * i);
            int2 neighborPos = pos + int2(offset);
            if (neighborPos.x >= 0 && neighborPos.y >= 0 && neighborPos.x < width && neighborPos.y < height) {
                float4 neighborPixel = inputTexture.read(uint2(neighborPos));
                float distance = length(float2(i));
                float weight = 1.0 / (distance + 1.0); // 거리에 반비례하는 가중치
                interpolatedPixel += neighborPixel * weight;
                weightSum += weight;
            }
        }
        
        // 가중치에 따라 보간된 픽셀 값을 쓰기
        if (weightSum > 0) {
            interpolatedPixel /= weightSum;
            outputTexture.write(interpolatedPixel, gid);
        } else {
            // 가중치 합이 0이면, 중심 픽셀 사용
            outputTexture.write(centerPixel, gid);
        }
        
    } else {
        // 주변 픽셀의 평균을 계산하여 보간합니다.
        float4 sum = float4(0.0);
        int count = 0;
        for (int i = 0; i < 8; ++i) {
            int2 curOffset = offsets[i];
            uint2 checkPos = uint2(clamp(pos + curOffset, int2(0, 0), int2(width - 1, height - 1)));
            sum += inputTexture.read(checkPos);
            ++count;
        }
        float4 average = sum / float(count);
        outputTexture.write(average, gid);
    }
}

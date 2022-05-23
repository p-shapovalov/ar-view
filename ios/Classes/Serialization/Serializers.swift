import Foundation
import ARKit

@available(iOS 11.3, *)
func serializeHitResult(_ transform: simd_float4x4) -> Dictionary<String, Any> {
    var hitResult = Dictionary<String, Any>(minimumCapacity: 1)
    hitResult["hitMatrix"] = serializeMatrix(transform)
    return hitResult
}

func serializeFrame(_ cameraMatrix: matrix_float4x4, _ projectionMatrix: matrix_float4x4) -> Dictionary<String, Any> {
    var frameResult = Dictionary<String, Any>(minimumCapacity: 2)
    frameResult["viewMatrix"] = serializeMatrix(cameraMatrix)
    frameResult["projectionMatrix"] = serializeMatrix(projectionMatrix)
    return frameResult
}

// The following code is adapted from Oleksandr Leuschenko' ARKit Flutter Plugin (https://github.com/olexale/arkit_flutter_plugin)

func serializeMatrix(_ matrix: simd_float4x4) -> Array<Float> {
    return [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3].flatMap { serializeArray($0) }
}

func serializeArray(_ array: simd_float4) -> Array<Float> {
    return [array[0], array[1], array[2], array[3]]
}

func serializeLocalTransformation(node: SCNNode?) -> Dictionary<String, Any?> {
    var serializedLocalTransformation = Dictionary<String, Any?>()

    let transform: [Float?] = [node?.transform.m11, node?.transform.m12, node?.transform.m13, node?.transform.m14, node?.transform.m21, node?.transform.m22, node?.transform.m23, node?.transform.m24, node?.transform.m31, node?.transform.m32, node?.transform.m33, node?.transform.m34, node?.transform.m41, node?.transform.m42, node?.transform.m43, node?.transform.m44]
    
    serializedLocalTransformation["name"] = node?.name
    serializedLocalTransformation["transform"] = transform

    return serializedLocalTransformation
}

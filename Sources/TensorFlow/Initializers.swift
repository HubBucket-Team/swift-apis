// Copyright 2019 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

public extension Tensor {
    /// Creates a tensor with the specified shape and a single, repeated scalar value.
    ///
    /// - Parameters:
    ///   - shape: The dimensions of the tensor.
    ///   - repeatedValue: The scalar value to repeat.
    @inlinable
    @available(*, deprecated, renamed: "init(repeating:shape:)")
    init(shape: TensorShape, repeating repeatedValue: Scalar) {
        self.init(repeating: repeatedValue, shape: shape)
    }

    /// Creates a tensor with the specified shape and a single, repeated scalar value.
    ///
    /// - Parameters:
    ///   - repeatedValue: The scalar value to repeat.
    ///   - shape: The dimensions of the tensor.
    @inlinable
    @differentiable(vjp: _vjpInit(repeating:shape:) where Scalar: TensorFlowFloatingPoint)
    init(repeating repeatedValue: Scalar, shape: TensorShape) {
        self = Raw.fill(
            dims: Tensor<Int32>(shape.dimensions.map(Int32.init)),
            value: Tensor(repeatedValue))
    }

    /// Creates a tensor by broadcasting the given scalar to a given rank with
    /// all dimensions being 1.
    @inlinable
    // @differentiable(where Scalar: TensorFlowFloatingPoint)
    init(broadcasting scalar: Scalar, rank: Int) {
        self = Tensor(scalar).reshaped(to: TensorShape(repeating: 1, count: rank))
    }

    /// Creates a tensor of shape `[4]` from a 4-tuple.
    /// - Note: This is intended for internal use, for example, to initialize a
    ///   tensor attribute from `convolved2D`'s `strides` argument.
    @inlinable
    internal init(_ scalars: (Scalar, Scalar, Scalar, Scalar)) {
        self.init([scalars.0, scalars.1, scalars.2, scalars.3])
    }
}

internal extension Tensor where Scalar: TensorFlowFloatingPoint {
    @inlinable
    static func _vjpInit(
        repeating repeatedValue: __owned Scalar,
        shape: __owned TensorShape
    ) -> (Tensor, (Tensor) -> Scalar) {
        return (Tensor(repeating: repeatedValue, shape: shape), {
            $0.sum().scalarized()
        })
    }
}

//===------------------------------------------------------------------------------------------===//
// Casting
//===------------------------------------------------------------------------------------------===//

public extension Tensor where Scalar: Numeric {
    /// Perform an element-wise type conversion from a `Bool` tensor.
    @inlinable
    init(_ other: Tensor<Bool>) {
        self = Raw.cast(other)
    }

    /// Perform an element-wise conversion from another `Tensor`.
    @inlinable
    @differentiable(
        vjp: _vjpCast where Scalar: TensorFlowFloatingPoint, OtherScalar: TensorFlowFloatingPoint)
    init<OtherScalar: Numeric>(_ other: Tensor<OtherScalar>) {
        self = Raw.cast(other)
    }
}

internal extension Tensor where Scalar: TensorFlowFloatingPoint {
    @inlinable
    static func _vjpCast<OtherScalar: TensorFlowFloatingPoint>(
        _ other: __owned Tensor<OtherScalar>
    ) -> (Tensor, (Tensor) -> Tensor<OtherScalar>) {
        (Tensor(other), { v in Tensor<OtherScalar>(v) })
    }
}

//===------------------------------------------------------------------------------------------===//
// Stacking / Concatenating / Tiling
//===------------------------------------------------------------------------------------------===//

public extension Tensor {
    /// Creates a tensor from an array of tensors (which may themselves be scalars).
    @inlinable
    @differentiable(vjp: _vjpInitElements where Scalar: TensorFlowFloatingPoint)
    init(_ elements: [Tensor]) {
        self = Raw.pack(elements)
    }

    /// Stacks `tensors`, along the `axis` dimension, into a new tensor with rank one higher than
    /// the current tensor and each tensor in `tensors`.
    ///
    /// Given that `tensors` all have shape `[A, B, C]`, and `tensors.count = N`, then:
    /// - if `axis == 0` then the resulting tensor will have the shape `[N, A, B, C]`.
    /// - if `axis == 1` then the resulting tensor will have the shape `[A, N, B, C]`.
    /// - etc.
    ///
    /// For example:
    /// ```
    /// // 'x' is [1, 4]
    /// // 'y' is [2, 5]
    /// // 'z' is [3, 6]
    /// Tensor(stacking: [x, y, z]) // is [[1, 4], [2, 5], [3, 6]]
    /// Tensor(stacking: [x, y, z], alongAxis: 1) // is [[1, 2, 3], [4, 5, 6]]
    /// ```
    ///
    /// This is the opposite of `Tensor.unstacked(alongAxis:)`.
    ///
    /// - Parameters:
    ///   - tensors: Tensors to stack.
    ///   - axis: Dimension along which to stack. Negative values wrap around.
    ///
    /// - Precondition: All tensors must have the same shape.
    /// - Precondition: `axis` must be in the range `[-rank, rank)`, where `rank` is the rank of the
    ///   provided tensors.
    ///
    /// - Returns: The stacked tensor.
    @inlinable
    @differentiable(vjp: _vjpStacking where Scalar: TensorFlowFloatingPoint)
    init(stacking tensors: [Tensor], alongAxis axis: Int = 0) {
        self = Raw.pack(tensors, axis: Int64(axis))
    }

    /// Concatenates `tensors` along the `axis` dimension.
    ///
    /// Given that `tensors[i].shape = [D0, D1, ... Daxis(i), ...Dn]`, then the concatenated result
    /// has shape `[D0, D1, ... Raxis, ...Dn]`, where `Raxis = sum(Daxis(i))`. That is, the data
    /// from the input tensors is joined along the `axis` dimension.
    ///
    /// For example:
    /// ```
    /// // t1 is [[1, 2, 3], [4, 5, 6]]
    /// // t2 is [[7, 8, 9], [10, 11, 12]]
    /// Tensor(concatenating: [t1, t2]) // is [[1, 2, 3], [4, 5, 6], [7, 8, 9], [10, 11, 12]]
    /// Tensor(concatenating: [t1, t2], alongAxis: 1) // is [[1, 2, 3, 7, 8, 9], [4, 5, 6, 10, 11, 12]]
    ///
    /// // t3 has shape [2, 3]
    /// // t4 has shape [2, 3]
    /// Tensor(concatenating: [t3, t4]) // has shape [4, 3]
    /// Tensor(concatenating: [t3, t4], alongAxis: 1) // has shape [2, 6]
    /// ```
    ///
    /// - Note: If you are concatenating along a new axis consider using
    ///   `Tensor.init(stacking:alongAxis:)`.
    ///
    /// - Parameters:
    ///   - tensors: Tensors to concatenate.
    ///   - axis: Dimension along which to concatenate. Negative values wrap around.
    ///
    /// - Precondition: All tensors must have the same rank and all dimensions except `axis`
    ///   must be equal.
    /// - Precondition: `axis` must be in the range `[-rank, rank)`, where `rank` is the rank of the
    ///   provided tensors.
    ///
    /// - Returns: The concatenated tensor.
    @inlinable
    @differentiable(vjp: _vjpConcatenating where Scalar: TensorFlowFloatingPoint)
    init(concatenating tensors: [Tensor], alongAxis axis: Int = 0) {
        precondition(tensors.count > 0)
        self = Raw.concatV2(tensors, axis: Tensor<Int32>(Int32(axis)))
    }
}

internal extension Tensor where Scalar: TensorFlowFloatingPoint {
    @inlinable
    static func _vjpInitElements(
        _ elements: __owned [Tensor]
    ) -> (Tensor, (Tensor) -> Array<Tensor>.DifferentiableView) {
        _vjpStacking(stacking: elements)
    }

    @inlinable
    static func _vjpStacking(
        stacking tensors: __owned [Tensor],
        alongAxis axis: __owned  Int = 0
    ) -> (Tensor, (Tensor) -> Array<Tensor>.DifferentiableView) {
        (Tensor(stacking: tensors, alongAxis: axis), { v in
            Array<Tensor>.DifferentiableView(v.unstacked(alongAxis: axis))
        })
    }

    @inlinable
    static func _vjpConcatenating(
        concatenating tensors: __owned [Tensor],
        alongAxis axis: __owned Int = 0
    ) -> (Tensor, (Tensor) -> Array<Tensor>.DifferentiableView) {
        let result = Tensor<Scalar>(concatenating: tensors, alongAxis: axis)
        let posAxis = axis < 0 ? axis + tensors[0].rank : axis
        let sizes = Tensor<Int32>(stacking: tensors.map { $0.shapeTensor[posAxis] })
        return (result, { [count = tensors.count] v in
            if count == 1 { return Array<Tensor>.DifferentiableView([v]) }
            let splits = v.split(sizes: sizes, alongAxis: posAxis)
            return Array<Tensor>.DifferentiableView(splits)
        })
    }
}

//===------------------------------------------------------------------------------------------===//
// Numeric
//===------------------------------------------------------------------------------------------===//

public extension Tensor where Scalar: Numeric {
    /// Creates a tensor with all scalars set to zero.
    ///
    /// - Parameter shape: Shape of the tensor.
    @inlinable
    init(zeros shape: TensorShape) {
        self.init(repeating: 0, shape: shape)
    }

    /// Creates a tensor with all scalars set to one.
    ///
    /// - Parameter shape: Shape of the tensor.
    @inlinable
    init(ones shape: TensorShape) {
        self.init(repeating: 1, shape: shape)
    }

    /// Creates a tensor with all scalars set to zero that has the same shape and type as the provided
    /// tensor.
    ///
    /// - Parameter other: Tensor whose shape and data type to use.
    @inlinable
    init(zerosLike other: Tensor) {
        self = Raw.zerosLike(other)
    }

    /// Creates a tensor with all scalars set to one that has the same shape and type as the provided
    /// tensor.
    ///
    /// - Parameter other: Tensor whose shape and data type to use.
    @inlinable
    init(onesLike other: Tensor) {
        self = Raw.onesLike(other)
    }

    /// Creates a 1-D tensor representing a sequence from a starting value to, but not including,
    /// an end value, stepping by the specified amount.
    ///
    /// - Parameters:
    ///   - start: The starting value to use for the sequence. If the sequence
    ///     contains any values, the first one is `start`.
    ///   - end: An end value to limit the sequence. `end` is never an element of
    ///     the resulting sequence.
    ///   - stride: The amount to step by with each iteration. `stride` must be
    ///     positive.
    @inlinable
    init(rangeFrom start: Scalar, to end: Scalar, stride: Scalar) {
        self = Raw.range(start: Tensor(start), limit: Tensor(end), delta: Tensor(stride))
    }

    /// Creates a 1-D tensor representing a sequence from a starting value to, but not including, an
    /// end value, stepping by the specified amount.
    ///
    /// - Parameters:
    ///   - start: The starting value to use for the sequence. If the sequence contains any values,
    ///     the first one is `start`.
    ///   - end: An end value to limit the sequence. `end` is never an element of the resulting
    ///     sequence.
    ///   - stride: The amount to step by with each iteration. `stride` must be positive.
    @inlinable
    init(rangeFrom start: Tensor<Scalar>, to end: Tensor<Scalar>, stride: Tensor<Scalar>) {
        self = Raw.range(start: start, limit: end, delta: stride)
    }

    /// Creates a one-hot tensor at given indices. The locations represented by
    /// `indices` take value `onValue` (`1` by default), while all other locations
    /// take value `offValue` (`0` by default). If the input `indices` is rank
    /// `n`, the new tensor will have rank `n+1`. The new axis is created at
    /// dimension `axis` (by default, the new axis is appended at the end).
    ///
    /// If `indices` is a scalar, the new tensor's shape will be a vector of
    /// length `depth`.
    ///
    /// If `indices` is a vector of length `features`, the output shape will be:
    ///     features x depth, if axis == -1
    ///     depth x features, if axis == 0
    ///
    /// If `indices` is a matrix (batch) with shape `[batch, features]`, the
    /// output shape will be:
    ///     batch x features x depth, if axis == -1
    ///     batch x depth x features, if axis == 1
    ///     depth x batch x features, if axis == 0
    ///
    /// - Parameters:
    ///   - indices: A `Tensor` of indices.
    ///   - depth: A scalar defining the depth of the one hot dimension.
    ///   - onValue: A scalar defining the value at the location referred to by
    ///     some index in `indices`.
    ///   - offValue: A scalar defining the value at a location that is not
    ///     referred to by any index in `indices`.
    ///   - axis: The axis to fill. The default is `-1`, a new inner-most axis.
    @inlinable
    init(
        oneHotAtIndices indices: Tensor<Int32>,
        depth: Int,
        onValue: Scalar = 1,
        offValue: Scalar = 0,
        axis: Int = -1
    ) {
        self = Raw.oneHot(
            indices: indices,
            depth: Tensor<Int32>(Int32(depth)),
            onValue: Tensor(onValue),
            offValue: Tensor(offValue),
            axis: Int64(axis))
    }
}

public extension Tensor where Scalar: TensorFlowFloatingPoint {
    /// Creates a 1-D tensor representing a sequence from a starting value, up to and
    /// including an end value, spaced evenly to generate the number of values specified.
    ///
    /// - Parameters:
    ///   - start: The starting value to use for the sequence. If the sequence contains any values,
    ///     the first one is `start`.
    ///   - end: An end value to limit the sequence. `end` is the last element of the resulting
    ///     sequence.
    ///   - count: The number of values in the resulting sequence. `count` must be positive.
    @inlinable
    init(linearSpaceFrom start: Scalar, to end: Scalar, count: Int) {
        self = Raw.linSpace(
            start: Tensor(start), stop: Tensor(end), num: Tensor<Int32>(Int32(count)))
    }

    /// Creates a 1-D tensor representing a sequence from a starting value, up to and
    /// including an end value, spaced evenly to generate the number of values specified.
    ///
    /// - Parameters:
    ///   - start: The starting value to use for the sequence. If the sequence contains any values,
    ///     the first one is `start`.
    ///   - end: An end value to limit the sequence. `end` is the last element of the resulting
    ///     sequence.
    ///   - count: The number of values in the resulting sequence. `count` must be positive.
    ///
    /// - Precondition: `start`, `to`, and `count` must be Tensors containing a single Scalar value.
    @inlinable
    init(linearSpaceFrom start: Tensor<Scalar>, to end: Tensor<Scalar>, count: Tensor<Int32>) {
        self = Raw.linSpace(start: start, stop: end, num: count)
    }
}

//===------------------------------------------------------------------------------------------===//
// Random
//===------------------------------------------------------------------------------------------===//

public extension Tensor where Scalar: TensorFlowIndex {
    /// Creates a tensor with the specified shape, randomly sampling scalar values from a uniform 
    /// distribution between `lowerBound` and `upperBound`.
    ///
    /// - Parameters:
    ///   - shape: The dimensions of the tensor.
    ///   - lowerBound: The lower bound of the distribution.
    ///   - upperBound: The upper bound of the distribution.
    ///   - seed: The seed value.
    init(
        randomUniform shape: TensorShape,
        lowerBound: Tensor<Scalar> = Tensor<Scalar>(0),
        upperBound: Tensor<Scalar> = Tensor<Scalar>(1),
        seed: TensorFlowSeed = Context.local.randomSeed
    ) {
        self = Raw.statelessRandomUniformInt(
            shape: Tensor<Int32>((0..<shape.rank).map { Int32(shape[$0]) }),
            seed: Tensor<Int32>([seed.graph, seed.op]),
            minval: lowerBound,
            maxval: upperBound)
    }
}

public extension Tensor where Scalar: TensorFlowFloatingPoint {
    /// Creates a tensor with the specified shape, randomly sampling scalar values from a uniform 
    /// distribution between `lowerBound` and `upperBound`.
    ///
    /// - Parameters:
    ///   - shape: The dimensions of the tensor.
    ///   - lowerBound: The lower bound of the distribution.
    ///   - upperBound: The upper bound of the distribution.
    ///   - seed: The seed value.
    init(
        randomUniform shape: TensorShape,
        lowerBound: Tensor<Scalar> = Tensor<Scalar>(0),
        upperBound: Tensor<Scalar> = Tensor<Scalar>(1),
        seed: TensorFlowSeed = Context.local.randomSeed
    ) {
        let sample: Tensor<Scalar> = Raw.statelessRandomUniform(
            shape: Tensor<Int32>((0..<shape.rank).map { Int32(shape[$0]) }),
            seed: Tensor<Int32>([seed.graph, seed.op]))
        self = (upperBound - lowerBound) * sample + lowerBound
    }

    /// Creates a tensor with the specified shape, randomly sampling scalar values from a normal 
    /// distribution.
    ///
    /// - Parameters:
    ///   - shape: The dimensions of the tensor.
    ///   - mean: The mean of the distribution.
    ///   - standardDeviation: The standard deviation of the distribution.
    ///   - seed: The seed value.
    init(
        randomNormal shape: TensorShape,
        mean: Tensor<Scalar> = Tensor<Scalar>(0),
        standardDeviation: Tensor<Scalar> = Tensor<Scalar>(1),
        seed: TensorFlowSeed = Context.local.randomSeed
    ) {
        let sample: Tensor<Scalar> = Raw.statelessRandomNormal(
            shape: Tensor<Int32>((0..<shape.rank).map { Int32(shape[$0]) }),
            seed: Tensor<Int32>([seed.graph, seed.op]))
        self = standardDeviation * sample + mean
    }
}

// TODO: Can become fileprivate after the 0.4 release.
internal extension Tensor where Scalar: TensorFlowFloatingPoint {
    static func glorot(
        fromStandardUniform randomUniform: __shared Tensor<Scalar>,
        shape: __shared TensorShape
    ) -> Tensor<Scalar> {
        let spatialDimCount = shape.count - 2
        let receptiveField = shape[0..<spatialDimCount].contiguousSize
        let fanIn = shape[shape.count - 2] * receptiveField
        let fanOut = shape[shape.count - 1] * receptiveField
        let minusOneToOne = 2 * randomUniform - 1
        return Scalar.sqrt(Scalar(6) / Scalar(fanIn + fanOut)) * minusOneToOne
    }
}

public extension Tensor where Scalar: TensorFlowFloatingPoint {
    /// Creates a tensor by performing Glorot uniform initialization for the specified shape,
    /// randomly sampling scalar values from a uniform distribution between `-limit` and `limit`,
    /// generated by the default random number generator, where limit is
    /// `sqrt(6 / (fanIn + fanOut))` and `fanIn`/`fanOut` represent the number of input and output
    /// features multiplied by the receptive field if present.
    ///
    /// - Parameters:
    ///   - shape: The dimensions of the tensor.
    init(glorotUniform shape: TensorShape, seed: TensorFlowSeed = Context.local.randomSeed) {
        let uniform = Tensor(randomUniform: shape, seed: seed)
        self = Tensor.glorot(fromStandardUniform: uniform, shape: shape)
    }
}

// TODO: Can become fileprivate after the 0.4 release.
internal extension Tensor where Scalar: TensorFlowFloatingPoint {
    static func glorot(
        fromStandardNormal standardNormal: __shared Tensor<Scalar>,
        shape: __shared TensorShape
    ) -> Tensor<Scalar> {
        let spatialDimCount = shape.count - 2
        let receptiveField = shape[0..<spatialDimCount].contiguousSize
        let fanIn = shape[shape.count - 2] * receptiveField
        let fanOut = shape[shape.count - 1] * receptiveField
        let minusOneToOne = 2 * standardNormal - 1
        return Scalar.sqrt(Scalar(2) / Scalar(fanIn + fanOut)) * minusOneToOne
    }
}

public extension Tensor where Scalar: TensorFlowFloatingPoint {
    /// Creates a tensor by performing Glorot normal initialization for the specified shape,
    /// randomly sampling scalar values from a uniform distribution between `-limit` and `limit`,
    /// generated by the default random number generator, where limit is
    /// `sqrt(2 / (fanIn + fanOut))` and `fanIn`/`fanOut` represent the number of input and output
    /// features multiplied by the receptive field if present.
    ///
    /// - Parameters:
    ///   - shape: The dimensions of the tensor.
    init(glorotNormal shape: TensorShape, seed: TensorFlowSeed = Context.local.randomSeed) {
        let normal = Tensor(randomNormal: shape, seed: seed)
        self = Tensor.glorot(fromStandardNormal: normal, shape: shape)
    }
}

public extension Tensor where Scalar: TensorFlowFloatingPoint {
    /// Creates an orthogonal matrix or tensor. 
    ///
    /// If the shape of the tensor to initialize is two-dimensional, it is initialized with an 
    /// orthogonal matrix obtained from the QR decomposition of a matrix of random numbers drawn 
    /// from a normal distribution. If the matrix has fewer rows than columns then the output will 
    /// have orthogonal rows. Otherwise, the output will have orthogonal columns.
    /// 
    /// If the shape of the tensor to initialize is more than two-dimensional, a matrix of shape 
    /// `[shape[0] * ... * shape[rank - 2], shape[rank - 1]]` is initialized.  The matrix is 
    /// subsequently reshaped to give a tensor of the desired shape.
    ///
    /// - Parameters:
    ///   - shape: The shape of the tensor.
    ///   - gain: A multiplicative factor to apply to the orthogonal tensor.
    ///   - seed: A tuple of two integers to seed the random number generator.
    init(
        orthogonal shape: TensorShape,
        gain: Tensor<Scalar> = Tensor<Scalar>(1),
        seed: TensorFlowSeed = Context.local.randomSeed
    ) {
        let rowCount = shape.dimensions.dropLast().reduce(1, *)
        let columnCount = shape[shape.rank - 1]
        var flatShape: TensorShape 
        if rowCount < columnCount {
            flatShape = [columnCount, rowCount]
        } else {
            flatShape = [rowCount, columnCount]
        }
        let normal = Tensor(randomNormal: flatShape, seed: seed)
        var (q, r) = normal.qrDecomposition(fullMatrices: false)
        let d = r.diagonalPart()
        q *= sign(d)
        if rowCount < columnCount {
            q = q.transposed()
        } 
        self = q.reshaped(to: shape) * gain 
    }
}

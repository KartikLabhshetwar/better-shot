# MLX Framework

Apple's machine learning framework with M5 chip neural accelerator support.

## MLX Basics

```swift
import MLX

// ✅ Load and run ML model with MLX
func runMLXModel() async throws {
    let model = try await MLXModel.load(from: modelURL)

    // Leverages M5 neural accelerators automatically
    let input = MLXArray(data: inputData)
    let output = try await model.predict(input)

    print("Prediction: \(output)")
}
```

## Neural Accelerator Access (M5)

```swift
// ✅ Optimize for M5 chip
func configureForM5() {
    MLX.configuration.useNeuralAccelerators = true
    MLX.configuration.preferredDevice = .neuralEngine
}

// ✅ Check hardware capabilities
func checkMLXCapabilities() -> Bool {
    MLX.neuralAcceleratorsAvailable
}
```

## Training on Device

```swift
// ✅ On-device model training
func trainModel() async throws {
    let trainer = MLXTrainer(model: model)
    trainer.configuration.device = .neuralEngine

    for epoch in 0..<numEpochs {
        let loss = try await trainer.train(epoch: epoch, data: trainingData)
        print("Epoch \(epoch): Loss = \(loss)")
    }

    try await trainer.save(to: modelURL)
}
```

## Resources

- [MLX Documentation](https://ml-explore.github.io/mlx/)
- [M5 Neural Engine Guide](https://developer.apple.com/documentation/coreml)

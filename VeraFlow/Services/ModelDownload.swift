import Foundation

// The ONLY app file allowed to reference URLSession or other networking (SPEC §6.2, §14.1).
// `NetworkPolicyTests` fails the build's test run if networking shows up anywhere else.
//
// Allowed traffic: Apple speech assets (AssetInventory, OS-managed), the one-time FluidAudio
// Core ML model download, and StoreKit. Nothing here ever sends user data.
//
// FluidAudio 0.15.7 downloads its Core ML models itself (Parakeet v3 for the M3 benchmark, the
// offline diarizer in M4) from Hugging Face into Application Support/FluidAudio/Models.
// M4 evaluates bundling those models in the app so this file can stay empty.

enum ModelDownload {
    /// Where FluidAudio fetches its models from. Shown in Settings → About (SPEC §14.1).
    /// Verified against FluidAudio 0.15.7 (`ModelRegistry.baseURL`, repos `FluidInference/…-coreml`).
    static let diarizationModelSourceDescription = "Hugging Face (FluidInference), downloaded once by FluidAudio"
}

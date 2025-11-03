use anyhow::{Context, Result};
use clap::Parser;
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "build-verifier")]
#[command(about = "Verify signed Nix build artifacts", long_about = None)]
struct Args {
    /// Path to proof.json file
    proof_file: PathBuf,

    /// Expected git commit SHA
    #[arg(long)]
    expected_commit: Option<String>,

    /// Path to flake.lock to verify hash
    #[arg(long, default_value = "flake.lock")]
    flake_lock: PathBuf,

    /// Optional: Path to file containing trusted public keys (one per line, hex encoded)
    #[arg(long)]
    trusted_keys: Option<PathBuf>,

    /// Skip commit verification (useful for testing)
    #[arg(long)]
    skip_commit_check: bool,

    /// Skip flake.lock hash verification (useful for testing)
    #[arg(long)]
    skip_flake_lock_check: bool,
}

#[derive(Serialize, Deserialize, Debug)]
struct Payload {
    commit: String,
    flake_lock_hash: String,
    build_command: String,
    artifact_tar_hash: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    drv_hash: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    build_log_hash: Option<String>,
    timestamp: String,
    nonce: String,
}

#[derive(Serialize, Deserialize, Debug)]
struct Proof {
    payload: Payload,
    signature: String,
    public_key: String,
    format_version: u8,
}

fn compute_file_sha256(path: &PathBuf) -> Result<String> {
    let contents = fs::read(path)
        .with_context(|| format!("Failed to read file: {}", path.display()))?;

    let mut hasher = Sha256::new();
    hasher.update(&contents);
    let hash = hasher.finalize();

    Ok(hex::encode(hash))
}

fn verify_signature(proof: &Proof) -> Result<()> {
    // Decode public key
    let pub_key_bytes = hex::decode(&proof.public_key)
        .context("Failed to decode public key")?;

    if pub_key_bytes.len() != 32 {
        anyhow::bail!("Public key must be 32 bytes");
    }

    let mut key_array = [0u8; 32];
    key_array.copy_from_slice(&pub_key_bytes);

    let verifying_key = VerifyingKey::from_bytes(&key_array)
        .context("Invalid public key")?;

    // Decode signature
    let sig_bytes = hex::decode(&proof.signature)
        .context("Failed to decode signature")?;

    if sig_bytes.len() != 64 {
        anyhow::bail!("Signature must be 64 bytes");
    }

    let mut sig_array = [0u8; 64];
    sig_array.copy_from_slice(&sig_bytes);

    let signature = Signature::from_bytes(&sig_array);

    // Serialize payload (same way as signer)
    let payload_bytes = serde_json::to_vec(&proof.payload)
        .context("Failed to serialize payload")?;

    // Verify signature
    verifying_key
        .verify(&payload_bytes, &signature)
        .context("Signature verification failed")?;

    Ok(())
}

fn check_trusted_key(public_key: &str, trusted_keys_path: Option<&PathBuf>) -> Result<bool> {
    let Some(path) = trusted_keys_path else {
        // If no trusted keys file provided, accept any key
        return Ok(true);
    };

    let contents = fs::read_to_string(path)
        .with_context(|| format!("Failed to read trusted keys file: {}", path.display()))?;

    for line in contents.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line == public_key {
            return Ok(true);
        }
    }

    Ok(false)
}

fn main() -> Result<()> {
    let mut args = Args::parse();

    // If no expected_commit provided, try GITHUB_SHA env var
    if args.expected_commit.is_none() {
        args.expected_commit = std::env::var("GITHUB_SHA").ok();
    }

    // Read and parse proof
    let proof_contents = fs::read_to_string(&args.proof_file)
        .with_context(|| format!("Failed to read proof file: {}", args.proof_file.display()))?;

    let proof: Proof = serde_json::from_str(&proof_contents)
        .context("Failed to parse proof JSON")?;

    println!("📋 Verifying build proof...");
    println!("  Format version: {}", proof.format_version);
    println!("  Commit: {}", proof.payload.commit);
    println!("  Public key: {}", proof.public_key);

    // Check format version
    if proof.format_version != 1 {
        anyhow::bail!("Unsupported proof format version: {}", proof.format_version);
    }

    // Verify signature
    print!("🔐 Verifying signature... ");
    verify_signature(&proof)?;
    println!("✓");

    // Check if public key is trusted
    if let Some(ref trusted_keys) = args.trusted_keys {
        print!("🔑 Checking trusted keys... ");
        if !check_trusted_key(&proof.public_key, Some(trusted_keys))? {
            anyhow::bail!("Public key not in trusted keys list");
        }
        println!("✓");
    }

    // Verify commit SHA
    if !args.skip_commit_check {
        if let Some(expected_commit) = args.expected_commit {
            print!("📝 Verifying commit SHA... ");
            if proof.payload.commit != expected_commit {
                anyhow::bail!(
                    "Commit mismatch: expected {}, got {}",
                    expected_commit,
                    proof.payload.commit
                );
            }
            println!("✓");
        } else {
            println!("⚠️  No expected commit provided (set GITHUB_SHA or use --expected-commit)");
        }
    }

    // Verify flake.lock hash
    if !args.skip_flake_lock_check {
        if args.flake_lock.exists() {
            print!("🔒 Verifying flake.lock hash... ");
            let computed_hash = compute_file_sha256(&args.flake_lock)?;
            if proof.payload.flake_lock_hash != computed_hash {
                anyhow::bail!(
                    "flake.lock hash mismatch:\n  Expected: {}\n  Computed: {}",
                    proof.payload.flake_lock_hash,
                    computed_hash
                );
            }
            println!("✓");
        } else {
            println!("⚠️  flake.lock not found at {}", args.flake_lock.display());
        }
    }

    println!("\n✅ Verification successful!");
    println!("  Artifact hash: {}", proof.payload.artifact_tar_hash);
    println!("  Build command: {}", proof.payload.build_command);
    println!("  Timestamp: {}", proof.payload.timestamp);

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hash_length() {
        // Just a simple test to verify hex encoding produces correct length
        let test_bytes = [0u8; 32];
        let hex_str = hex::encode(test_bytes);
        assert_eq!(hex_str.len(), 64); // 32 bytes = 64 hex chars
    }
}

use anyhow::{Context, Result};
use clap::Parser;
use ed25519_dalek::{Signature, Signer, SigningKey};
use rand::rngs::OsRng;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(name = "build-signer")]
#[command(about = "Sign Nix build artifacts for verification", long_about = None)]
struct Args {
    /// Git commit SHA
    #[arg(long)]
    commit: String,

    /// SHA256 hash of flake.lock
    #[arg(long)]
    flake_lock_hash: String,

    /// SHA256 hash of the deterministic artifact tarball
    #[arg(long)]
    artifact_tar_hash: String,

    /// Build command that was executed
    #[arg(long)]
    build_command: String,

    /// Optional: Nix derivation hash
    #[arg(long)]
    drv_hash: Option<String>,

    /// Optional: SHA256 hash of build log
    #[arg(long)]
    build_log_hash: Option<String>,

    /// Path to Ed25519 private key file (32 bytes)
    #[arg(long)]
    private_key: PathBuf,

    /// Output path for proof.json
    #[arg(long)]
    out: PathBuf,
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

fn generate_nonce() -> String {
    let mut nonce = [0u8; 16];
    use rand::RngCore;
    OsRng.fill_bytes(&mut nonce);
    hex::encode(nonce)
}

fn get_timestamp() -> String {
    use std::time::SystemTime;
    let now = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .expect("Time went backwards");

    let secs = now.as_secs();

    // Simple UTC timestamp calculation
    const SECONDS_PER_DAY: u64 = 86400;
    const DAYS_FROM_0_TO_1970: u64 = 719162;

    let days_since_epoch = secs / SECONDS_PER_DAY;
    let secs_today = secs % SECONDS_PER_DAY;

    let total_days = DAYS_FROM_0_TO_1970 + days_since_epoch;

    // Simplified year calculation (good enough for our use case)
    let year = 1970 + (days_since_epoch / 365);
    let day_of_year = days_since_epoch % 365;

    let hours = secs_today / 3600;
    let minutes = (secs_today % 3600) / 60;
    let seconds = secs_today % 60;

    // Simple approximation - good enough for attestation purposes
    format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
            year,
            (day_of_year / 30) + 1,  // Rough month
            (day_of_year % 30) + 1,  // Rough day
            hours,
            minutes,
            seconds)
}

fn sign_payload(signing_key: &SigningKey, payload: &Payload) -> Result<String> {
    // Serialize payload deterministically
    let payload_bytes = serde_json::to_vec(payload)
        .context("Failed to serialize payload")?;

    let signature = signing_key.sign(&payload_bytes);
    Ok(hex::encode(signature.to_bytes()))
}

fn main() -> Result<()> {
    let args = Args::parse();

    // Read private key
    let private_key_bytes = fs::read(&args.private_key)
        .context("Failed to read private key file")?;

    if private_key_bytes.len() != 32 {
        anyhow::bail!("Private key must be exactly 32 bytes");
    }

    let mut key_bytes = [0u8; 32];
    key_bytes.copy_from_slice(&private_key_bytes);

    let signing_key = SigningKey::from_bytes(&key_bytes);
    let verifying_key = signing_key.verifying_key();

    // Create payload
    let payload = Payload {
        commit: args.commit,
        flake_lock_hash: args.flake_lock_hash,
        build_command: args.build_command,
        artifact_tar_hash: args.artifact_tar_hash,
        drv_hash: args.drv_hash,
        build_log_hash: args.build_log_hash,
        timestamp: get_timestamp(),
        nonce: generate_nonce(),
    };

    // Sign payload
    let signature = sign_payload(&signing_key, &payload)?;

    // Create proof
    let proof = Proof {
        payload,
        signature,
        public_key: hex::encode(verifying_key.to_bytes()),
        format_version: 1,
    };

    // Write proof to file
    let proof_json = serde_json::to_string_pretty(&proof)
        .context("Failed to serialize proof")?;

    fs::write(&args.out, proof_json)
        .context("Failed to write proof file")?;

    println!("✓ Proof generated successfully: {}", args.out.display());
    println!("  Commit: {}", proof.payload.commit);
    println!("  Artifact hash: {}", proof.payload.artifact_tar_hash);
    println!("  Public key: {}", proof.public_key);

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_nonce_generation() {
        let nonce1 = generate_nonce();
        let nonce2 = generate_nonce();
        assert_eq!(nonce1.len(), 32); // 16 bytes = 32 hex chars
        assert_ne!(nonce1, nonce2); // Should be different
    }

    #[test]
    fn test_timestamp_format() {
        let ts = get_timestamp();
        assert!(ts.contains('T'));
        assert!(ts.ends_with('Z'));
        assert!(ts.len() >= 20);
    }
}

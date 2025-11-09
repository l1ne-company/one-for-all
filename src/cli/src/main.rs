use std::{
    env,
    ffi::{OsStr, OsString},
    path::{Path, PathBuf},
    process::Command,
};

use anyhow::{anyhow, bail, Context, Result};
use clap::{Args, Parser, Subcommand, ValueHint};

const DEFAULT_EXAMPLE_DIR: &str = "src/lang/rust/examples";
const DEFAULT_NIXPKGS_FROM: &str = "src/lang/rust/test#nixpkgs";

#[derive(Parser)]
#[command(
    name = "one",
    version,
    author,
    about = "Local helper for one-for-all",
    long_about = "Wrapper CLI around the repository's primary Nix workflows."
)]
struct Cli {
    /// Path to the repository root (defaults to the current directory)
    #[arg(
        global = true,
        short,
        long,
        default_value = ".",
        value_hint = ValueHint::DirPath
    )]
    root: PathBuf,
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Build one of the flake outputs with `nix build`
    Build(BuildArgs),
    /// Run `nix flake check` for the repository
    Check(CheckArgs),
    /// Run the bundled CI helper (`nix run .#ci`)
    Ci(CiArgs),
    /// Run `nix flake check` for a template/example project
    Test(TestArgs),
    /// Enter the devshell or run a command inside it via `nix develop`
    Develop(DevelopArgs),
}

#[derive(Args)]
struct BuildArgs {
    /// Flake attribute to build (omit the leading `#`)
    #[arg(short, long, value_name = "ATTR")]
    attribute: Option<String>,
    /// Extra arguments forwarded to `nix build`
    #[arg(long = "nix-arg", value_name = "ARG")]
    nix_args: Vec<String>,
}

#[derive(Args)]
struct CheckArgs {
    /// Show build logs (`-L`)
    #[arg(short, long)]
    verbose: bool,
    /// Pass `--no-build` to `nix flake check`
    #[arg(long)]
    no_build: bool,
    /// Allow `nix flake check` to update the lockfile
    #[arg(long)]
    allow_write_lock: bool,
    /// Extra arguments forwarded to `nix flake check`
    #[arg(long = "nix-arg", value_name = "ARG")]
    nix_args: Vec<String>,
}

#[derive(Args)]
struct TestArgs {
    /// Example/template name (relative to `src/lang/rust/examples`) or a custom path
    #[arg(value_name = "NAME_OR_PATH")]
    example: String,
    /// nixpkgs input referenced by the example (overridden via `--override-input`)
    #[arg(long, value_name = "INPUT", default_value = DEFAULT_NIXPKGS_FROM)]
    nixpkgs_from: String,
    /// Extra arguments forwarded to `nix flake check`
    #[arg(long = "nix-arg", value_name = "ARG")]
    nix_args: Vec<String>,
}

#[derive(Args)]
struct DevelopArgs {
    /// Devshell attribute to use (omit the leading `#`)
    #[arg(short, long, value_name = "ATTR")]
    attribute: Option<String>,
    /// Additional flags forwarded to `nix develop`
    #[arg(long = "nix-arg", value_name = "ARG")]
    nix_args: Vec<String>,
    /// Command to execute inside the devshell
    #[arg(long, value_name = "PROGRAM")]
    command: Option<String>,
    /// Arguments for `--command` (only valid when `--command` is set)
    #[arg(last = true, value_name = "ARG", requires = "command")]
    command_args: Vec<String>,
}

#[derive(Args)]
struct CiArgs {
    /// Extra arguments forwarded to `nix flake check` (after `--`)
    #[arg(last = true, value_name = "ARG")]
    extra_args: Vec<String>,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let root = canonicalize_root(&cli.root)?;

    match cli.command {
        Commands::Build(args) => run_build(&root, args),
        Commands::Check(args) => run_check(&root, args),
        Commands::Ci(args) => run_ci(&root, args),
        Commands::Test(args) => run_tests(&root, args),
        Commands::Develop(args) => run_develop(&root, args),
    }
}

fn canonicalize_root(root: &Path) -> Result<PathBuf> {
    let path = if root.is_absolute() {
        root.to_path_buf()
    } else {
        env::current_dir()
            .context("failed to determine current directory")?
            .join(root)
    };

    path.canonicalize()
        .with_context(|| format!("failed to resolve repository root: {}", path.display()))
}

fn run_build(root: &Path, args: BuildArgs) -> Result<()> {
    let installable = build_installable(root, args.attribute.as_deref());
    let mut cmd_args = Vec::with_capacity(4 + args.nix_args.len());
    cmd_args.push(oss("build"));
    cmd_args.push(oss("--accept-flake-config"));
    cmd_args.push(oss("--print-build-logs"));
    cmd_args.extend(args.nix_args.into_iter().map(OsString::from));
    cmd_args.push(installable);

    run_command(OsStr::new("nix"), &cmd_args, root)
}

fn run_check(root: &Path, args: CheckArgs) -> Result<()> {
    let mut cmd_args = Vec::with_capacity(5 + args.nix_args.len());
    cmd_args.push(oss("flake"));
    cmd_args.push(oss("check"));
    cmd_args.push(oss("--accept-flake-config"));
    cmd_args.push(oss("--print-build-logs"));
    if args.verbose {
        cmd_args.push(oss("-L"));
    }
    if args.no_build {
        cmd_args.push(oss("--no-build"));
    }
    if !args.allow_write_lock {
        cmd_args.push(oss("--no-write-lock-file"));
    }
    cmd_args.extend(args.nix_args.into_iter().map(OsString::from));
    cmd_args.push(OsString::from(root));

    run_command(OsStr::new("nix"), &cmd_args, root)
}

fn run_tests(root: &Path, args: TestArgs) -> Result<()> {
    let TestArgs {
        example,
        nixpkgs_from,
        nix_args,
    } = args;
    let example_path = resolve_example_path(root, &example);
    if !example_path.exists() {
        return Err(anyhow!(
            "example {:?} does not exist (resolved to {})",
            example,
            example_path.display()
        ));
    }

    let mut cmd_args = Vec::with_capacity(10 + nix_args.len());
    cmd_args.push(oss("flake"));
    cmd_args.push(oss("check"));
    cmd_args.push(example_path.into_os_string());
    cmd_args.push(oss("--override-input"));
    cmd_args.push(oss("one-for-all"));
    cmd_args.push(OsString::from(format!("path:{}", root.display())));
    cmd_args.push(oss("--override-input"));
    cmd_args.push(oss("nixpkgs"));
    cmd_args.push(normalize_flake_ref(root, &nixpkgs_from));
    cmd_args.push(oss("--accept-flake-config"));
    cmd_args.push(oss("--no-write-lock-file"));
    cmd_args.push(oss("--print-build-logs"));
    cmd_args.extend(nix_args.into_iter().map(OsString::from));

    run_command(OsStr::new("nix"), &cmd_args, root)
}

fn run_develop(root: &Path, args: DevelopArgs) -> Result<()> {
    let installable = build_installable(root, args.attribute.as_deref());
    let mut cmd_args = Vec::with_capacity(5 + args.nix_args.len() + args.command_args.len());
    cmd_args.push(oss("develop"));
    cmd_args.push(oss("--accept-flake-config"));
    cmd_args.extend(args.nix_args.into_iter().map(OsString::from));
    cmd_args.push(installable);
    if let Some(command) = args.command {
        cmd_args.push(oss("--command"));
        cmd_args.push(command.into());
        cmd_args.extend(args.command_args.into_iter().map(OsString::from));
    }

    run_command(OsStr::new("nix"), &cmd_args, root)
}

fn run_ci(root: &Path, args: CiArgs) -> Result<()> {
    let mut cmd_args = Vec::with_capacity(5 + args.extra_args.len());
    cmd_args.push(oss("run"));
    cmd_args.push(oss("--accept-flake-config"));
    cmd_args.push(build_installable(root, Some("ci")));
    if !args.extra_args.is_empty() {
        cmd_args.push(oss("--"));
        cmd_args.extend(args.extra_args.into_iter().map(OsString::from));
    }

    run_command(OsStr::new("nix"), &cmd_args, root)
}

fn build_installable(root: &Path, attribute: Option<&str>) -> OsString {
    let mut installable = OsString::from(root);
    if let Some(attr) = attribute {
        installable.push("#");
        installable.push(attr.trim_start_matches('#'));
    }
    installable
}

fn resolve_example_path(root: &Path, selector: &str) -> PathBuf {
    let candidate = PathBuf::from(selector);
    if candidate.is_absolute() {
        return candidate;
    }

    if looks_like_relative_path(selector) {
        return root.join(candidate);
    }

    root.join(DEFAULT_EXAMPLE_DIR).join(selector)
}

fn looks_like_relative_path(input: &str) -> bool {
    if input.is_empty() {
        return false;
    }

    let has_drive_prefix =
        input.len() > 1 && input.as_bytes()[1] == b':' && input.as_bytes()[0].is_ascii_alphabetic();

    has_drive_prefix
        || input.starts_with(['.', '/', '\\'])
        || (!input.contains(':')
            && (input.contains('/')
                || input.contains('\\')
                || input.contains(std::path::MAIN_SEPARATOR)))
}

fn normalize_flake_ref(root: &Path, reference: &str) -> OsString {
    let (path_part, attr_part) = reference
        .split_once('#')
        .map_or((reference, None), |(path, attr)| (path, Some(attr)));

    if looks_like_relative_path(path_part) {
        let mut result = OsString::from(format!("path:{}", root.join(path_part).display()));
        if let Some(attr) = attr_part {
            result.push("#");
            result.push(attr);
        }
        result
    } else {
        OsString::from(reference)
    }
}

fn run_command(program: &OsStr, args: &[OsString], cwd: &Path) -> Result<()> {
    let display = format_command(program, args);
    println!("> {}", display);

    let status = Command::new(program)
        .args(args)
        .current_dir(cwd)
        .status()
        .with_context(|| format!("failed to run {}", display))?;

    if status.success() {
        Ok(())
    } else {
        bail!("{} exited with {}", display, status);
    }
}

fn format_command(program: &OsStr, args: &[OsString]) -> String {
    let mut parts = vec![program.to_string_lossy().into_owned()];
    parts.extend(args.iter().map(|arg| quote_arg(arg)));
    parts.join(" ")
}

fn quote_arg(arg: &OsStr) -> String {
    let s = arg.to_string_lossy();
    if s.chars()
        .any(|c| c.is_whitespace() || matches!(c, '\'' | '"'))
    {
        let escaped = s.replace('\'', "'\\''");
        format!("'{}'", escaped)
    } else {
        s.into_owned()
    }
}

fn oss(value: impl Into<OsString>) -> OsString {
    value.into()
}

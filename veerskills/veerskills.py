#!/usr/bin/env python3
"""
VeerSkills CLI Launcher
Provides an easy command-line interface to launch the VeerSkills smart contract audit engine.
"""

import sys
import os
import subprocess
import argparse

def ensure_claude_cli():
    """Ensure the claude CLI is installed."""
    if not shutil.which("claude"):
        print("Error: The 'claude' CLI tool is not installed or not in PATH.")
        print("Install it via npm: npm i -g @anthropic-ai/claude-code")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description="VeerSkills - Ultimate Smart Contract Security Audit")
    parser.add_argument("target", nargs="*", help="Files, directories, or additional arguments for the audit")
    parser.add_argument("--mode", choices=["quick", "standard", "deep", "beast"], default="standard", 
                        help="Audit mode. quick(15-30m), standard(2-4h), deep(4-8h), beast(8+h).")
    parser.add_argument("--continue", "-c", dest="resume", action="store_true", 
                        help="Resume the last audit session from ./veerskills-outputs/")
    
    args = parser.parse_args()
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    skill_path = os.path.join(script_dir, "SKILL.md")
    
    if not os.path.exists(skill_path):
        print(f"Error: Could not find SKILL.md at {skill_path}")
        sys.exit(1)
        
    prompt_args = " ".join(args.target)
    if args.resume:
        prompt_args += " --continue"
        
    print(f"=====================================================================")
    print(f" Launching VeerSkills Engine")
    print(f" Mode: {args.mode.upper()}")
    print(f" Target: {prompt_args if prompt_args.strip() else 'Current Directory'}")
    print(f"=====================================================================")
    
    cmd = [
        "claude", 
        "-p", skill_path, 
        f"Follow the VeerSkills pipeline perfectly. Run a {args.mode} audit on: {prompt_args}"
    ]
    
    try:
        if sys.platform == "win32":
            subprocess.run(" ".join(cmd), shell=True, check=True)
        else:
            subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError:
        print("VeerSkills execution finished with an error or was interrupted.")
    except KeyboardInterrupt:
        print("\nAudit cancelled by user.")
        sys.exit(0)

if __name__ == "__main__":
    import shutil
    ensure_claude_cli()
    main()

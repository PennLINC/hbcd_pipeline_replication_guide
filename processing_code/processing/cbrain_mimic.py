#!/usr/bin/env python3
"""
CBRAIN Mimic Tool

A Python script to process BIDS data with CBRAIN-like functionality.
"""

import argparse
import os
import sys
import json
import shutil
from pathlib import Path
from typing import Dict, Any, Optional


def parse_arguments() -> argparse.Namespace:
    """Parse command line arguments using argparse."""
    parser = argparse.ArgumentParser(
        description="CBRAIN Mimic Tool for BIDS data processing",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    
    # Required arguments
    parser.add_argument(
        "--dest-dir",
        type=str,
        required=True,
        help="Destination directory for processed data"
    )
    
    parser.add_argument(
        "--participant-label",
        type=str,
        required=True,
        help="Participant label (subject ID)"
    )
    
    parser.add_argument(
        "--session-id",
        type=str,
        required=True,
        help="Session ID"
    )
    
    parser.add_argument(
        "--midb-bids-dir",
        type=str,
        required=True,
        help="Path to MIDB BIDS directory"
    )
    
    parser.add_argument(
        "--cbrain-json",
        type=str,
        required=True,
        help="Path to CBRAIN JSON configuration file"
    )
    
    return parser.parse_args()


def load_cbrain_config(config_path: str) -> Dict[str, Any]:
    """Load CBRAIN configuration from JSON file."""
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
        return config
    except FileNotFoundError:
        print(f"Error: CBRAIN JSON file not found: {config_path}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in CBRAIN config file: {e}")
        sys.exit(1)


def process_participant_data(
    source_dir: str,
    dest_dir: str,
    participant_label: str,
    session_id: str,
    config: Dict[str, Any],
) -> None:
    """Process participant data according to CBRAIN configuration."""
    dest_path = Path(dest_dir)

    files_to_copy = config["invoke"]["all_to_keep"]

    for fname in files_to_copy:
        source_path = Path(source_dir) / participant_label / fname
        if not source_path.exists():
            raise FileNotFoundError(f"Source file not found: {source_path}")
        dest_path = Path(dest_dir) / participant_label / fname
        dest_parent = dest_path.parent
        dest_parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source_path, dest_path)


def main():
    """Main function."""
    # Parse command line arguments
    args = parse_arguments()
    
    # Print configuration if verbose
    print("CBRAIN Mimic Tool Configuration:")
    print(f"  Destination Directory: {args.dest_dir}")
    print(f"  Participant Label: {args.participant_label}")
    print(f"  Session ID: {args.session_id}")
    print(f"  MIDB BIDS Directory: {args.midb_bids_dir}")
    print(f"  CBRAIN JSON: {args.cbrain_json}")
    print()
    
    # Load CBRAIN configuration
    config = load_cbrain_config(args.cbrain_json)

    
    # Process participant data
    process_participant_data(
        args.midb_bids_dir,
        args.dest_dir,
        args.participant_label,
        args.session_id,
        config,
    )
    
    print("CBRAIN Mimic processing completed successfully!")


if __name__ == "__main__":
    main() 

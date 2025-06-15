#!/usr/bin/env python3

import argparse
from datetime import datetime, timezone
import getpass
import os
from pathlib import Path
import re
import subprocess
import sys
from typing import Dict, Union
import yaml

from jinja2 import Environment, FileSystemLoader

if __name__ == "__main__":

    def get_ros_distros_str(ros_distros: Dict[str, Dict[str, Union[str, int]]]) -> str:
        """
        Return a human-readable, column-aligned list of the available ROS variants.

        The function iterates through the mapping of variants loaded from the YAML file and
        constructs a multi-line string in which the colon after each distro name is vertically
        aligned.  The insertion order of the original mapping is preserved (Python ≥ 3.7
        guarantees that `dict` keeps insertion order).

        Parameters
        ----------
        ros_distros : dict[str, dict[str, str | int]]
            A dictionary whose keys are variant labels (e.g. noetic) and
            whose values contain at least the following keys:

            ros_distro : str
                Name of the ROS distribution (noetic, humble, …).
            ros_version : int
                ROS major version (1 or 2).
            ubuntu_version : str
                Ubuntu release the image is based on (e.g. 20.04).

        Returns
        -------
        str
            A multi-line string of the form::

                Available ROS distros:
                    noetic : ros1, ubuntu_20.04
                    humble : ros2, ubuntu_22.04
                    jazzy  : ros2, ubuntu_24.04
        """
        header = "Available ROS distros:"
        width = max(len(v["ros_distro"]) for v in ros_distros.values())
        lines = [
            f"{v['ros_distro']:<{width}}: ros{v['ros_version']}, ubuntu_{v['ubuntu_version']}"
            for v in ros_distros.values()
        ]
        return "\n".join([header, *lines])

    def img_exists_locally(img: str) -> bool:
        cmd = ["docker", "image", "inspect", img]
        # capture=True -> stdout y stderr redireted to PIPE (they are not shown in the terminal)
        # check=False  -> it does not throw exception if the image does not exist
        result = run_command(cmd, capture=True, check=False)
        return result.returncode == 0

    def is_valid_docker_img_name(name: str) -> bool:
        """
        Validate a Docker image name according to Docker's official naming rules.

        Format:
            [HOST[:PORT_NUMBER]/]PATH[:TAG]

        See: https://docs.docker.com/get-started/docker-concepts/building-images/build-tag-and-publish-an-image/#tagging-images
        """

        # Optional registry prefix: host (lower‑case letters, digits, dots, dashes)
        # with optional :PORT, followed by a slash.
        host_and_port_prefix = r"([a-z0-9.-]+(:[0-9]+)?/)?"

        # A separator inside a path component can be:
        #   • a single dot
        #   • one or two underscores
        #   • one or more dashes
        path_separator = r"(?:\.|_{1,2}|-+)"

        # A path component must start and end with an alphanumeric character,
        # separators are allowed only between alphanumerics.
        path_component = rf"[a-z0-9]+(?:{path_separator}[a-z0-9]+)*"

        # PATH = one or more components separated by '/'
        path_re = rf"{path_component}(/{path_component})*"

        # Optional TAG: colon + allowed characters (letters, digits, '_', '.', '-')
        tag_re = r"(:[a-zA-Z0-9_.-]+)?"

        # Full regex combining all parts
        full_re = re.compile(rf"^{host_and_port_prefix}{path_re}{tag_re}$")

        return bool(full_re.match(name))

    def run_command(
        cmd: list[str], capture: bool = False, check: bool = True, cwd: Path | None = None
    ) -> subprocess.CompletedProcess:
        return subprocess.run(cmd, check=check, text=True, capture_output=capture, cwd=cwd)

    # ----------------------------------------------------------------------------------------------
    # Main execution block
    # ----------------------------------------------------------------------------------------------
    this_file = Path(__file__).resolve()
    root_dir = this_file.parent
    ros_distros_yaml_file = root_dir.joinpath("ros_distros.yaml")

    if not ros_distros_yaml_file.is_file():
        print(f"Error: File '{ros_distros_yaml_file.resolve()}' is required")
        sys.exit(1)

    try:
        with open(ros_distros_yaml_file, "r") as f:
            ros_distros = yaml.safe_load(f)
    except (FileNotFoundError, yaml.YAMLError):
        print(f"Error: Could not read or parse the file '{ros_distros_yaml_file.resolve()}'", file=sys.stderr)
        sys.exit(1)

    parser = argparse.ArgumentParser(
        description=f"Builds a Docker image, with ROS(1|2), to execute the driver of a sensor and publish the captured data",
        allow_abbrev=False,  # Disable prefix matching
        add_help=False,  # Add custom help message
        formatter_class=lambda prog: argparse.RawTextHelpFormatter(prog, max_help_position=38),
    )

    parser.add_argument(
        "-h", "--help", action="help", default=argparse.SUPPRESS, help="Show this help message and exit"
    )

    parser.add_argument(
        "-c",
        "--cache",
        action="store_true",
        help="Reuse cached layers to optimize the time and resources needed to build the image.",
    )

    parser.add_argument(
        "-p",
        "--pull",
        action="store_true",
        help=(
            "If no local copy of the base image exists, Docker will download it automatically from\n"
            "the proper registry. If there is a local copy of the base image, Docker will get the\n"
            "version available in the proper registry, and if the version from the registry is newer\n"
            "than the local copy, it will be downloaded and used. If the local copy is the latest\n"
            "version, it will not be downloaded again.\n"
            "Without --pull Docker uses the local copy of the base image if it is available on the\n"
            "system. If no local copy exists, Docker will download it automatically.\n"
            "Usage of --pull is recommended to ensure an updated base image is used."
        ),
    )

    parser.add_argument(
        "ros_distro",
        type=str,
        default="humble",
        help=(f"{get_ros_distros_str(ros_distros)}"),
    )

    parser.add_argument(
        "dockerfile",
        type=str,
        help=("Path to the Dockerfile to build the Docker image"),
    )

    parser.add_argument(
        "img_id",
        type=str,
        help=("Image ID for the Docker image to build'"),
    )

    parser.add_argument(
        "--meta-title",
        type=str,
        default="Docker image to run a sensor",
        help='Title to include in the image\'s metadata (e.g "App")',
    )

    parser.add_argument(
        "--meta-desc",
        type=str,
        default="A Docker image to launch a sensor and publish the captured data",
        help="Description to include in the image's metadata",
    )

    parser.add_argument("--meta-authors", type=str, default=getpass.getuser(), help="Authors of the image")

    args = parser.parse_args()
    ros_distro = args.ros_distro
    dockerfile = Path(args.dockerfile.strip()).expanduser().resolve()
    img_id_to_build = args.img_id.strip()
    args.meta_title = args.meta_title.strip()
    args.meta_desc = args.meta_desc.strip()
    args.meta_authors = args.meta_authors.strip()

    if ros_distro not in ros_distros:
        print(f"Error: Invalid ROS distro '{ros_distro}'.\n{get_ros_distros_str(ros_distros)}", file=sys.stderr)
        sys.exit(1)

    ros_version = ros_distros[ros_distro]["ros_version"]
    ubuntu_version = ros_distros[ros_distro]["ubuntu_version"]

    if not dockerfile.is_file():
        print(f"Error: Dockerfile '{dockerfile.resolve()}' does not exist or is not a file", file=sys.stderr)
        sys.exit(1)

    if not is_valid_docker_img_name(img_id_to_build):
        print(f"Error: Invalid Docker image name: '{img_id_to_build}'", file=sys.stderr)
        sys.exit(1)

    creation_time = datetime.now(timezone.utc).strftime("%Y-%m-%d_%H-%M-%S")

    # With DOCKER_BUILDKIT enabled, we can use advanced build features like volume mounts, like:
    # RUN --mount=type=bind,source=...,target=... && <command>
    # Ref: https://docs.docker.com/build/buildkit/
    # docker-py doesn't support BuildKit, and has an issue open for almost 6 years
    # (https://github.com/docker/docker-py/issues/2230) so it doesn't seem like it is being added.
    # Therefore, we use the subprocess module to call docker build... so that we can enable
    # BuildKit, and thus mount volume during buil

    # Enables Docker BuildKit for advanced build features.
    os.environ["DOCKER_BUILDKIT"] = "1"

    cmd = [
        "docker",
        "build",
        "--file",
        str(dockerfile.resolve()),
        "--progress=plain",
    ]

    if args.pull:
        print(f"--pull specified. Docker build will attempt to pull/update base image '{base_img}'")
        cmd.append("--pull")

    if not args.cache:
        cmd.append("--no-cache")

    arguments = {
        "UBUNTU_VERSION": ubuntu_version,
        "ROS_DISTRO": ros_distro,
        "ROS_VERSION": ros_version,
    }

    for k, v in arguments.items():
        cmd += ["--build-arg", f"{k}={v}"]

    labels = {
        "org.opencontainers.image.created": datetime.now(timezone.utc).isoformat(),
        "org.opencontainers.image.title": args.meta_title,
        "org.opencontainers.image.description": args.meta_desc,
        "org.opencontainers.image.authors": args.meta_authors,
    }

    for k, v in labels.items():
        cmd += ["--label", f"{k}={v}"]

    cmd.extend(["--tag", img_id_to_build])
    context_dir = dockerfile.parent
    cmd.append(str(context_dir))

    log_dir = Path("/tmp")
    img_id_sanitized = img_id_to_build.replace(":", "_").replace("/", "_")
    timestamp_log = datetime.now(timezone.utc).strftime("%Y-%m-%d_%H-%M-%S")
    log_prefix = f"build_img_{img_id_sanitized}_{timestamp_log}"
    complete_log_file = log_dir.joinpath(f"{log_prefix}_complete.log")
    specific_log_file = log_dir.joinpath(f"{log_prefix}_specific.log")

    print(
        f"Building the Docker image '{img_id_to_build}' with Ubuntu '{ubuntu_version}' and 'ROS{ros_version}-{ros_distro}'"
    )

    exit_code = 0

    try:
        print("Executing command:")
        print(" ".join(cmd))

        with subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,  # Combine stdout and stderr
            text=True,  # Decode directly to strings
            bufsize=1,  # Enable line buffering for real-time output
        ) as process, open(complete_log_file, "w") as full_log:

            # Read each line of the subprocess's output as it is produced, i.e., in real-time.
            for line in process.stdout:
                print(line, end="", flush=True)
                full_log.write(line)  # Full log

            # Ensure the log file is flushed to disk.
            full_log.flush()
            # Wait for the process to finish and check the exit code
            process.wait()
            exit_code = process.returncode

            if exit_code == 0:
                print(f"\nDocker build process ended with SUCCESS for the image '{img_id_to_build}'")
            else:
                print(
                    f"\nDocker build process ended with FAILURE (exit code {exit_code}) for the image '{img_id_to_build}': {process.stderr.strip()}"
                )

            if complete_log_file.exists():
                if complete_log_file.stat().st_size > 0:
                    print(f"Log file '{complete_log_file}' is ready")

                    # Extract, from the complete log, those lines that match the pattern 'specific_log_pattern'.
                    specific_log_pattern = re.compile(r"(\[\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\])")
                    matches = 0

                    with complete_log_file.open("r") as fin, specific_log_file.open("w") as fout:
                        for line in fin:
                            if specific_log_pattern.search(line):
                                fout.write(line)
                                matches += 1

                    if matches == 0:
                        print("No matching specific log lines found.")
                        try:
                            specific_log_file.unlink()
                        except OSError as e:
                            print(f"Error: Could not remove log file: {e}", file=sys.stderr)
                            exit_code = exit_code if exit_code != 0 else 1
                    else:
                        print(f"Specific log file '{specific_log_file}' is ready.")
                else:
                    try:
                        complete_log_file.unlink(missing_ok=True)
                    except OSError as e:
                        print(f"Error: Could not remove log file: {e}", file=sys.stderr)
                        exit_code = exit_code if exit_code != 0 else 1
            else:
                print(f"Log file '{complete_log_file}' does not exist.")
    except KeyboardInterrupt:
        print("Aborted by user (Ctrl-C)")
    except Exception as e:
        print(f"Error: {e}")
    finally:
        sys.exit(exit_code)

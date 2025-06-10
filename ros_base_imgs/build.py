#!/usr/bin/env python3

import argparse
from datetime import datetime, timezone
import getpass
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from jinja2 import Environment, FileSystemLoader

if __name__ == "__main__":

    ROS_DISTROS: dict[str, str] = {
        "noetic": "1:20.04",
        "humble": "2:22.04",
        "jazzy": "2:24.04",
    }

    def get_ros_distros_str_for_help() -> str:
        lines = ["Available ROS distros:"]

        # Sort by ROS version, then Ubuntu version, then distro name for consistent help output
        sorted_distros = sorted(
            ROS_DISTROS.items(), key=lambda item: (int(item[1].split(":")[0]), item[1].split(":")[1], item[0])
        )

        for key, value in sorted_distros:
            ros_version, ubuntu_version = value.split(":")
            lines.append(f"    {key:<6}: ros{ros_version}, ubuntu {ubuntu_version}.")

        return "\n".join(lines)

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

    # --------------------------------------------------------------------------------------------------
    # Main execution block
    # --------------------------------------------------------------------------------------------------

    script_name = Path(__file__).name
    base_dir = Path(__file__).parent.resolve()

    parser = argparse.ArgumentParser(
        description="Builds a Docker image with and active user and ROS",
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
            "Checks if a newer version of the base image is available in the proper registry (e.g., Docker Hub).\n"
            "If a newer version is found, it downloads and uses it. If the latest version is already available\n"
            "locally it will not download it again. Without --pull Docker uses the local copy of the base image\n"
            "if it is available on the system. If no local copy exists, Docker will download it automatically.\n"
            "Usage of --pull is recommended to ensure an updated base image is used."
        ),
    )

    parser.add_argument(
        "-b", "--base-img", type=str, help="Base image. Default: ubuntu:X.Y, matched to the ROS distro."
    )

    parser.add_argument("img_user", type=str, help="User to run containers for the resulting Docker image")

    parser.add_argument("ros_distro", type=str, help=f"ROS distro.\n{get_ros_distros_str_for_help()}")

    parser.add_argument("img_id", type=str, help="Image ID for the resulting Docker image.")

    entrypoint_group = parser.add_mutually_exclusive_group()

    entrypoint_group.add_argument(
        "--use-base-img-entrypoint",
        action="store_true",
        help="The image will inherit the base image's entrypoint, if any. Do not use this option if you set a custom entrypoint",
    )

    entrypoint_group.add_argument(
        "--entrypoint",
        type=str,
        metavar="ENTRYPOINT_SCRIPT",
        help="Path to a custom entrypoint script to include in the Docker image (replaces the default entrypoint script)",
    )

    environment_group = parser.add_mutually_exclusive_group()

    environment_group.add_argument(
        "--no-environment",
        action="store_true",
        help="Do not use an environment script. Do not use this option if you set a custom environment script",
    )

    environment_group.add_argument(
        "--environment",
        type=str,
        metavar="ENVIRONMENT_SCRIPT",
        help="Path to a custom environment script to include in the Docker image (replaces the default environment script)",
    )

    parser.add_argument(
        "--meta-title",
        type=str,
        default="Docker image with ROS2-humble",
        help='Title to include in the image\'s metadata (e.g "App")',
    )

    parser.add_argument(
        "--meta-desc",
        type=str,
        default="Docker image for development and testing",
        help="Description to include in the image's metadata",
    )

    parser.add_argument("--meta-authors", type=str, default=getpass.getuser(), help="Authors of the image")

    args = parser.parse_args()
    base_img = args.base_img.strip() if args.base_img is not None else ""
    requested_user = args.img_user.strip()  # Required, so won't be empty
    requested_user_home = f"/home/{requested_user}" if requested_user != "root" else "/root"
    ros_distro = args.ros_distro.lower()  # Required, so won't be empty
    img_id_to_build = args.img_id.strip()  # Required, so won't be empty
    use_environment = not args.no_environment

    if ros_distro not in ROS_DISTROS:
        print(f"Error: Invalid ROS distro '{ros_distro}'. Allowed: {get_ros_distros_str_for_help()}")
        sys.exit(1)

    ros_version, ubuntu_version = ROS_DISTROS[ros_distro].split(":")

    if not base_img:
        base_img = f"ubuntu:{ubuntu_version}"

        if not is_valid_docker_img_name(base_img):  # Should be valid by construction, but just in case
            print(f"Error: Default base image '{base_img}' is invalid.", file=sys.stderr)
            sys.exit(1)

        print(f"No base image specified, defaulting to '{base_img}' for 'ROS{ros_version}-{ros_distro}'")
    elif not is_valid_docker_img_name(base_img):
        print(f"Error: Invalid Docker base image name: '{base_img}'", file=sys.stderr)
        sys.exit(1)

    if not is_valid_docker_img_name(img_id_to_build):
        print(f"Error: Invalid Docker image name: '{img_id_to_build}'", file=sys.stderr)
        sys.exit(1)

    if not requested_user or " " in requested_user:
        print(f"Error: Invalid user '{requested_user}'. No whitepaces allowed", file=sys.stderr)
        sys.exit(1)

    # Read ROS packages from the file 'packages_ros{ros_version}.txt'
    root_path = Path(__file__).expanduser().resolve().parent
    ros_packages_file = root_path.joinpath(f"packages_ros{ros_version}.txt")

    if not ros_packages_file.is_file():
        print(f"File '{str(ros_packages_file)}' not found.")
        sys.exit(1)

    with ros_packages_file.open("r") as f:
        ros_packages = f.read()

    if not ros_packages.strip():
        print(f"File '{str(ros_packages_file)}' is empty.")
        sys.exit(1)

    # Read extra ROS environment variables from the file 'env_vars_ros{ros_version}.txt'
    extra_ros_env_vars_file = root_path.joinpath(f"env_vars_ros{ros_version}.txt")

    if not extra_ros_env_vars_file.is_file():
        print(f"File '{str(extra_ros_env_vars_file)}' not found.")
        sys.exit(1)

    with extra_ros_env_vars_file.open("r") as f:
        extra_ros_env_vars = f.read()

    if not extra_ros_env_vars.strip():
        print(f"File '{str(extra_ros_env_vars_file)}' is empty.")
        sys.exit(1)

    # Items to use.
    # Source is relative to base_dir, destination relative to context_path)
    # (src_name, dst_name, is_executable)
    items_to_use = {
        "Dockerfile": [
            "Dockerfile.j2",
            {
                "use_base_img_entrypoint": args.use_base_img_entrypoint,
                "use_environment": use_environment,
                "extra_ros_env_vars": extra_ros_env_vars,
            },
            False,
        ],
        "deduplicate_path.sh": ["deduplicate_path.sh", True],
        "dot_bash_aliases": ["dot_bash_aliases", True],
        "install_base_system.sh": ["install_base_system.sh", True],
        "install_ros.sh": [
            "install_ros.j2",
            {"use_environment": use_environment, "ros_packages": ros_packages},
            True,
        ],
        "rosbuild.sh": [f"ros{ros_version}build.sh", True],
        "rosdep_init_update.sh": ["rosdep_init_update.sh", True],
    }

    if ros_version == "2":
        items_to_use["colcon_mixin_metadata.sh"] = [
            "colcon_mixin_metadata.sh",
            True,
        ]
        items_to_use["rosdep_ignored_keys.yaml"] = [
            "rosdep_ignored_keys_ros2.yaml",
            False,
        ]

    if not args.use_base_img_entrypoint:
        if args.entrypoint is not None:
            entrypoint = Path(args.entrypoint).expanduser().resolve()

            if not entrypoint.is_file() or entrypoint.stat().st_size == 0:
                print(f"Custom entrypoint file '{str(entrypoint)}' not found.")
                sys.exit(1)

            items_to_use["entrypoint.sh"] = [str(entrypoint), True]
        else:
            items_to_use["entrypoint.sh"] = ["entrypoint.sh", True]

    if use_environment:
        if args.environment is not None:
            environment = Path(args.environment).expanduser().resolve()

            if not environment.is_file() or environment.stat().st_size == 0:
                print(f"Custom environment file '{environment}' not found.")
                sys.exit(1)

            items_to_use["environment.sh"] = [str(environment), True]
        else:
            items_to_use["environment.sh"] = [
                f"environment_ros{ros_version}.j2",
                {"ros_distro": ros_distro},
                True,
            ]

    exit_code = 1
    complete_log_file = specific_log_file = None

    try:
        with tempfile.TemporaryDirectory(prefix="context_", dir="/tmp") as tmp_dir:
            context_dir = Path(tmp_dir)

            print(f"Created temporary context directory '{context_dir}'.")

            # Copy the items to use to the context directory.
            for key in sorted(items_to_use.keys()):
                dst_path = context_dir.joinpath(key)

                item = items_to_use[key]

                if item[0].startswith("/"):
                    src_path = Path(item[0])
                else:
                    src_path = root_path.joinpath(item[0])

                if not src_path.exists():
                    print(f"Required resource '{str(src_path)}' does not exist.")
                    sys.exit(1)

                if not src_path.is_file():
                    print(f"Required resource '{str(src_path)}' is not a file.")
                    sys.exit(1)

                if not dst_path.parent.exists():
                    dst_path.parent.mkdir(parents=True)

                print(f"Creating file '{dst_path}'.")

                if len(item) == 2:
                    shutil.copy2(src_path, dst_path)

                    if item[1]:
                        dst_path.chmod(0o775)
                    else:
                        dst_path.chmod(0o664)
                elif len(item) == 3:
                    context = item[1]

                    if context is None:
                        print(f"Context for Jinja2 rendering can't be None for element '{str(dst_path)}'.")
                        sys.exit(1)

                    if not isinstance(context, dict):
                        print(f"Context for Jinja2 rendering must be a dictionary for element '{str(dst_path)}'.")
                        sys.exit(1)

                    if not dst_path.parent.exists():
                        dst_path.parent.mkdir(parents=True)

                    jinja2_env = Environment(
                        loader=FileSystemLoader(src_path.parent), trim_blocks=True, lstrip_blocks=True
                    )
                    jinja2_template = jinja2_env.get_template(src_path.name)
                    rendered_text = jinja2_template.render(context)

                    with dst_path.open("w") as f:
                        f.write(rendered_text)

                    if item[2]:
                        dst_path.chmod(0o775)
                    else:
                        dst_path.chmod(0o664)

            creation_time = datetime.now(timezone.utc).strftime("%Y-%m-%d_%H-%M-%S")

            os.environ["DOCKER_BUILDKIT"] = "1"

            cmd = [
                "docker",
                "build",
                "--file",
                str(context_dir.joinpath("Dockerfile")),
                "--progress=plain",
            ]

            if not args.pull and not img_exists_locally(base_img):
                print(f"Base image '{base_img}' not found locally. Docker build will attempt to pull it")
            elif args.pull:
                print(f"--pull specified. Docker build will attempt to pull/update base image '{base_img}'")
                cmd.append("--pull")
            else:  # Not args.pull and image exists locally
                print(f"Using local base image '{base_img}'")

            if not args.cache:
                cmd.append("--no-cache")

            build_args = {
                "BASE_IMG": base_img,
                "REQUESTED_USER": requested_user,
                "REQUESTED_USER_HOME": requested_user_home,
                "ROS_DISTRO": ros_distro,
                "ROS_VERSION": ros_version,
            }

            for k, v in build_args.items():
                cmd += ["--build-arg", f"{k}={v}"]

            labels = {
                "org.opencontainers.image.created": datetime.now(timezone.utc).isoformat(),
                "org.opencontainers.image.title": args.meta_title.strip(),
                "org.opencontainers.image.authors": args.meta_authors.strip(),
                "org.opencontainers.image.description": args.meta_desc.strip(),
            }

            for k, v in labels.items():
                cmd += ["--label", f"{k}={v}"]

            cmd.extend(["--tag", img_id_to_build])
            cmd.append(str(context_dir))

            log_dir = Path("/tmp")
            img_id_sanitized = img_id_to_build.replace(":", "_").replace("/", "_")
            timestamp_log = datetime.now(timezone.utc).strftime("%Y-%m-%d_%H-%M-%S")
            log_prefix = f"build_img_{img_id_sanitized}_{timestamp_log}"
            complete_log_file = log_dir.joinpath(f"{log_prefix}_complete.log")
            specific_log_file = log_dir.joinpath(f"{log_prefix}_specific.log")

            print(
                f"Building the Docker image '{img_id_to_build}', using the base image '{base_img}', "
                f"with active user '{requested_user}' and 'ROS{ros_version}-{ros_distro}'"
            )
            print("Executing command:")
            print(" ".join(cmd))

            specific_log_pattern = re.compile(r"(\[\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\])")

            with subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,  # Line-buffered
            ) as process, open(complete_log_file, "w") as full_log:

                for line in process.stdout:
                    print(line, end="", flush=True)
                    full_log.write(line)

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

                # if the complete log file exists and has content, process the specific log
                # file to extract lines matching the specific log pattern.
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

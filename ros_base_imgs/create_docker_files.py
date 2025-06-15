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

    def create_items_to_install(
        base_img: str,
        img_user: str,
        ros_distro: str,
        ros_version: str,
        img_id_to_build: str,
        use_base_img_entrypoint: bool,
        use_environment: bool,
        use_host_nvidia_driver: bool,
        ros_packages_file: Path,
        extra_ros_env_vars_file: Path,
    ) -> dict[str, list[str | dict[str, str] | bool]]:

        if not ros_packages_file.is_file():
            print(f"File '{str(ros_packages_file)}' not found.")
            sys.exit(1)

        with ros_packages_file.open("r") as f:
            ros_packages = f.read()

        if not ros_packages.strip():
            print(f"File '{str(ros_packages_file)}' is empty.")
            sys.exit(1)

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
        items_to_install = {
            "Dockerfile": [
                "Dockerfile.j2",
                {
                    "base_img": base_img,
                    "img_user": img_user,
                    "ros_distro": ros_distro,
                    "ros_version": ros_version,
                    "use_base_img_entrypoint": use_base_img_entrypoint,
                    "use_environment": use_environment,
                    "extra_ros_env_vars": extra_ros_env_vars,
                },
                False,
            ],
            "build.py": [
                "build.j2",
                {
                    "base_img": base_img,
                    "img_id": img_id_to_build,
                    "img_user": img_user,
                    "ros_distro": ros_distro,
                    "ros_version": ros_version,
                },
                True,
            ],
            "deduplicate_path.sh": ["deduplicate_path.sh", True],
            "docker-compose.yaml": [
                "docker-compose.j2",
                {
                    "service": f"{img_id_to_build.replace(':', '_').replace('/', '_')}_cont",
                    "img_id": img_id_to_build,
                    "img_workspace_dir": f"/home/{img_user}/workspace",
                    "img_datasets_dir": f"/home/{img_user}/datasets",
                    "img_ssh_dir": f"/home/{img_user}/.ssh",
                    "img_gitconfig_file": f"/home/{img_user}/.gitconfig",
                    "use_host_nvidia_driver": use_host_nvidia_driver,
                    "ext_uid": f"{os.getuid()}",
                    "ext_upgid": f"{os.getgid()}",
                },
                False,
            ],
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
            items_to_install["colcon_mixin_metadata.sh"] = [
                "colcon_mixin_metadata.sh",
                True,
            ]
            items_to_install["rosdep_ignored_keys.yaml"] = [
                "rosdep_ignored_keys_ros2.yaml",
                False,
            ]

        if not args.use_base_img_entrypoint:
            items_to_install["entrypoint.sh"] = ["entrypoint.sh", True]

        if use_environment:
            items_to_install["environment.sh"] = [f"environment_ros{ros_version}.j2", {"ros_distro": ros_distro}, True]

        if not args.use_host_nvidia_driver:
            items_to_install["install_mesa_packages.sh"] = [
                "install_default_mesa_packages.sh",
                True,
            ]

        return items_to_install

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

    def install_items(items_to_install: dict[str, list[str | dict[str, str] | bool]], context_dir: Path) -> None:
        # Copy the items to use to the context directory.
        for key in sorted(items_to_install.keys()):
            dst_path = context_dir.joinpath(key)

            item = items_to_install[key]

            # If the item[0] is None, it means that the key, that can be a file or a directory, must
            # be created, not copied from a resource.
            src_path = None

            if item[0] is not None:
                src_path = root_path.joinpath(item[0])

                if not src_path.exists():
                    print(f"Required resource '{str(src_path)}' does not exist.")
                    sys.exit(1)

            # len = 1 -> directory
            #    src_path is None -> create an empty directory
            #    src_path is not None -> copy the directory recursively
            # len = 2 -> file with permissions
            #    src_path is None -> create an empty file with permissions
            #    src_path is not None -> copy the file with permissions
            # len = 3 -> file with Jinja2 rendering and permissions
            #    src_path is None -> raise an exception, not allowed
            #    src_path is not None -> copy the file with Jinja2 rendering and permissions
            if len(item) == 1:
                print(f"Creating directory '{dst_path}'")

                if src_path is not None:
                    if not src_path.is_dir():
                        print(f"Required resource '{str(src_path)}' is not a directory.")
                        sys.exit(1)

                    if not dst_path.parent.exists():
                        dst_path.parent.mkdir(parents=True)

                    shutil.copytree(src_path, dst_path, copy_function=shutil.copy2)
                    dst_path.chmod(0o775)
                else:
                    dst_path.mkdir(parents=True)
            elif len(item) == 2:
                print(f"Creating file '{dst_path}'")

                if src_path is not None:
                    if not src_path.is_file():
                        print(f"Required resource '{str(src_path)}' is not a file.")
                        sys.exit(1)

                    if not dst_path.parent.exists():
                        dst_path.parent.mkdir(parents=True)

                    shutil.copy2(src_path, dst_path)
                else:
                    dst_path.touch()

                if item[1]:
                    dst_path.chmod(0o775)
                else:
                    dst_path.chmod(0o664)
            elif len(item) == 3:
                print(f"Creating file '{dst_path}'")

                if src_path is None:
                    print(f"Relative source path can't be empty for element '{str(dst_path)}'.")
                    sys.exit(1)

                if not src_path.is_file():
                    print(f"Required resource '{str(src_path)}' is not a file.")
                    sys.exit(1)

                context = item[1]

                if context is None:
                    print(f"Context for Jinja2 rendering can't be None for element '{str(dst_path)}'.")

                if not isinstance(context, dict):
                    print(f"Context for Jinja2 rendering must be a dictionary for element '{str(dst_path)}'.")

                if not dst_path.parent.exists():
                    dst_path.parent.mkdir(parents=True)

                jinja2_env = Environment(loader=FileSystemLoader(src_path.parent), trim_blocks=True, lstrip_blocks=True)
                jinja2_template = jinja2_env.get_template(src_path.name)
                rendered_text = jinja2_template.render(context)

                with dst_path.open("w") as f:
                    f.write(rendered_text)

                if item[2]:
                    dst_path.chmod(0o775)
                else:
                    dst_path.chmod(0o664)

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
        "-b", "--base-img", type=str, help="Base image. Default: ubuntu:X.Y, matched to the ROS distro."
    )

    parser.add_argument("img_user", type=str, help="User to run containers for the resulting Docker image")

    parser.add_argument("ros_distro", type=str, help=f"ROS distro.\n{get_ros_distros_str_for_help()}")

    parser.add_argument("img_id", type=str, help="Image ID for the resulting Docker image.")

    parser.add_argument(
        "--use-base-img-entrypoint",
        action="store_true",
        help="The image will inherit the base image's entrypoint, if any. Do not use this option if you set a custom entrypoint",
    )

    parser.add_argument(
        "--no-environment",
        action="store_true",
        help="Do not use an environment script. Do not use this option if you set a custom environment script",
    )

    parser.add_argument("--use-host-nvidia-driver", action="store_true", help="Use host's NVIDIA driver")

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
    img_user = args.img_user.strip()  # Required, so won't be empty
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

    if not img_user or " " in img_user:
        print(f"Error: Invalid user '{img_user}'. No whitepaces allowed", file=sys.stderr)
        sys.exit(1)

    # Read ROS packages from the file 'packages_ros{ros_version}.txt'
    root_path = Path(__file__).expanduser().resolve().parent
    ros_packages_file = root_path.joinpath(f"packages_ros{ros_version}.txt")
    # Read extra ROS environment variables from the file 'env_vars_ros{ros_version}.txt'
    extra_ros_env_vars_file = root_path.joinpath(f"env_vars_ros{ros_version}.txt")

    # with tempfile.TemporaryDirectory(prefix="context_", dir="/tmp") as tmp_dir:
    context_dir = Path(tempfile.mkdtemp(prefix="context_", dir="/tmp"))

    print(f"Created temporary directory '{context_dir}'.")

    install_items(
        create_items_to_install(
            base_img,
            img_user,
            ros_distro,
            ros_version,
            img_id_to_build,
            args.use_base_img_entrypoint,
            use_environment,
            args.use_host_nvidia_driver,
            ros_packages_file,
            extra_ros_env_vars_file,
        ),
        context_dir,
    )

# creditcoin-aws deployment snippets

Collection of scripts, tips to deploy a credticoin container using podman on an AWS instance.  Done mainly to help a friend and keeping it around in case  it helps anyone else. At the moment all that's here is the USER-DATA script which can be inserted into the USER-DATA section of a launch template and used in an autoscaling configuration as it uses instance data to define the Systemd podman ExecStart in the unit file.

The following AWS USER-DATA script is to provision a Podman CreditCoin Miner/Validator Node
in AWS in a generic manner.  At the very least, you may want to change the DEFAULT in the
node name to something meaningful.  You can either paste it in the console or b64 encode it
for CLI use.

Notables
1. - Uses Podman rather than Docker - initial version runs as system (root)
   subsequent version will run in systemd user context as I have tested that approach with no issues.
   - Using root was the only way to limit CPU under a certain discount cloud vps provider...
   (hint: add --cpus="5.45" as the first option after "podman run" to keep 8 cores under 70% - YMMV.)
2. - I deploy on RHEL so the build is geared towards dnf flavors.  Have deployed the container under
   podman running eon Ubuntu 20 & 22 with no issues.  Tweak to your needs.
3. - Installs a custom SELinux profile to accomodate the specific container requirements.
   Udica is your friend. Don't disable SELinux!
4. - Data is stored locally at /app/ctcmn
5. - Sets node IP and node name from current node when container starts
6. - Sets hostname to match nodename.

# SeLinux profile
We used Udica (https://github.com/containers/udica) to generate a container-specific policy from the running container, you can too!
1. podman ps -q # collect the container ID
2. podman inspect <ContainerID> > container.json # export container configuration
3. udica -j container.json <my-container-name> # convert to policy file.

That’s it! You just created a custom SELinux security policy <my-container-name>.cil - feel free to examine it with a text editor or continue on to loading the policy.

4. semodule -i <my-containeri-name>.cil /usr/share/udica/templates/{base_container.cil,net_container.cil,home_container.cil} # Insert policy
5. Update the ExecStart line to leverage the new module & restart the container.


ToDo:
1. Reconfigure to run as non-root user.
2. Open to suggestions.

Coming:
Launch Template json
CF Template


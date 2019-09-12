# repel-infrastructure

A repo for code to manage REPEL project infrastructure.

To the extent possible, Dockerfiles and other app-level infrastructure should live in sub-project modular repos.  Scripts here should primarily call on those to deploy to servers.

See the [project infrastructure design document](https://docs.google.com/document/d/1MD81IEwqdTyH5zr4KjySGakCTA0dh4WMvFoj2V0t1iQ/edit?usp=sharing).

-  For ansible deploys, secure variables stored in secure.yml.  A `.vault` file with the decryption key is required.

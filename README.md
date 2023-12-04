# Go tools image

This image is used to build Go projects. It contains the Go compiler (from the official golang container) as well as additional tools that help with building projects.

## Updating

First you need to confirm that the image is building and that the changes are present:

1. update [`Dockerfile`](Dockerfile) and add all the changes you want to add to this base image.
2. run `make build` and make sure it passes.
3. run `make shell` and test your changes are indeed present.
4. run `make test` to make sure all components are working.

Once you confirmed the build passes and the changes are as expected do the following:

1. create a commit with `Makefile`, `Dockerfile` and `image-test` changes.
2. push the changes and create a new pull request.

After the PR gets reviewed you need to check all the different places where `grafana-build-tools` is used and update accordingly. Here [`git grep`](http://git-scm.com/docs/git-grep) is your friend:

* `git grep grafana-build-tools` will list all places where `grafana-build-tools` is used.
* `git grep grafana-build-tools:$OLDVERSION` same as before, but more restrictive.

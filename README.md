# ProtonMail IMAP/SMTP Bridge Docker Container

![build badge](https://github.com/bostrot/protonmail-bridge-docker/workflows/build%20from%20source/badge.svg)
![deb badge](https://github.com/bostrot/protonmail-bridge-docker/workflows/pack%20from%20deb/badge.svg)
![update badge](https://github.com/bostrot/protonmail-bridge-docker/workflows/update%20check/badge.svg)

This is an unofficial Docker container of the [ProtonMail Bridge](https://protonmail.com/bridge/). Some of the scripts are based on [Hendrik Meyer's work](https://gitlab.com/T4cC0re/protonmail-bridge-docker).

This is a fork of [shenxn/protonmail-bridge-docker](https://github.com/shenxn/protonmail-bridge-docker) that adds TLS-terminated IMAPS/SMTPS ports and keeps itself pinned to the latest Proton Bridge release automatically.

GitHub: [https://github.com/bostrot/protonmail-bridge-docker](https://github.com/bostrot/protonmail-bridge-docker)

Images: `ghcr.io/bostrot/protonmail-bridge`

## Tags

There are two types of images.
 - `deb`: Images based on the official [.deb release](https://protonmail.com/bridge/install). It only supports the `amd64` architecture.
 - `build`: Images based on the [source code](https://github.com/ProtonMail/proton-bridge). It supports `amd64`, `arm64`, `arm/v7` and `riscv64`.

tag | description
 -- | --
`latest` | latest `deb` image
`[version]` | `deb` images
`build` | latest `build` image
`[version]-build` | `build` images

Every Proton Bridge release also gets a matching git tag and GitHub release in this repository, published automatically by the `update check` workflow.

## Ports

port | protocol | encryption
 -- | -- | --
`993` | IMAP | implicit TLS (IMAPS) — **recommended**
`465` | SMTP | implicit TLS (SMTPS) — **recommended**
`143` | IMAP | plaintext unless the client negotiates STARTTLS
`25` | SMTP | plaintext unless the client negotiates STARTTLS

## Initialization

To initialize and add account to the bridge, run the following command.

```
docker run --rm -it -v protonmail:/root ghcr.io/bostrot/protonmail-bridge:build init
```

If you want to use Docker Compose instead, you can create a copy of the provided example [docker-compose.yml](docker-compose.yml) file, modify it to suit your needs, and then run the following command:

```
docker compose run protonmail-bridge init
```

Wait for the bridge to startup, then you will see a prompt appear for [Proton Mail Bridge interactive shell](https://proton.me/support/bridge-cli-guide). Use the `login` command and follow the instructions to add your account into the bridge. Then use `info` to see the configuration information (username and password). After that, use `exit` to exit the bridge. You may need `CTRL+C` to exit the docker entirely.

## Run

To run the container, use the following command.

```
docker run -d --name=protonmail-bridge -v protonmail:/root -p 1993:993/tcp -p 1465:465/tcp --restart=unless-stopped ghcr.io/bostrot/protonmail-bridge:build
```

Or, if using Docker Compose, use the following command.

```
docker compose up -d
```

Then point your mail client at port `1993` for IMAP and `1465` for SMTP, with SSL/TLS enabled, using the username and password that `info` printed during initialization.

## Encryption

Proton Bridge always offers STARTTLS on its own IMAP and SMTP listeners, so this container was never fully plaintext. There are two problems with relying on that alone:

 - **STARTTLS is optional.** Nothing stops a client from authenticating in the clear on port `143` or `25`.
 - **The bridge's own certificate is issued for `127.0.0.1` only.** The bridge is designed to run on the same machine as the mail client, so its self-signed certificate has a single `IP:127.0.0.1` SAN. As soon as the connection is forwarded out of the container, that certificate can no longer be validated by name, which is why guides for this image usually tell you to switch certificate checking off entirely.

This image therefore terminates TLS itself on ports `993` (IMAPS) and `465` (SMTPS), using a certificate that matches how the container is actually reached, and forwards to the bridge over the container's own loopback interface. The plaintext hop never leaves the container.

The certificate is self-signed, generated on first start, and stored in the mounted volume at `/root/tls/`, so it survives restarts and recreations. Its SHA-256 fingerprint is printed to the container log at every start:

```
docker logs protonmail-bridge | grep -A5 'TLS certificate fingerprint'
```

### Making clients trust it

Copy the certificate out of the volume and import it into your client (or your system trust store):

```
docker cp protonmail-bridge:/root/tls/bridge.crt ./bridge.crt
```

### Certificate names

By default the certificate is valid for `localhost`, `protonmail-bridge` and `127.0.0.1`. If you reach the container under any other name or address, list it in `BRIDGE_TLS_SAN` so hostname verification succeeds:

```
-e BRIDGE_TLS_SAN='DNS:mail.example.com,DNS:localhost,IP:127.0.0.1'
```

Changing `BRIDGE_TLS_SAN` does not regenerate an existing certificate. Delete `/root/tls/` in the volume and restart the container to issue a new one.

### Bringing your own certificate

To use a real certificate instead (from Let's Encrypt, an internal CA, whatever), mount it into the container as `/root/tls/bridge.crt` and `/root/tls/bridge.key`. If both files are present they are used as-is and nothing is generated.

### Environment variables

variable | default | description
 -- | -- | --
`BRIDGE_TLS_SAN` | `DNS:localhost,DNS:protonmail-bridge,IP:127.0.0.1` | Subject alternative names for the generated certificate.
`BRIDGE_TLS_CN` | `protonmail-bridge` | Common name for the generated certificate.
`BRIDGE_TLS_DIR` | `/root/tls` | Where the certificate and key live.
`BRIDGE_TLS_ONLY` | `false` | Set to `true` to stop opening the plaintext `143` and `25` listeners at all.

## Security

Please be aware that publishing these ports exposes your bridge to the network. Remember to use a firewall if you are going to run this in an untrusted network or on a machine that has a public IP address. You can also publish the ports to localhost only, which is the same behaviour as the official bridge package.

```
docker run -d --name=protonmail-bridge -v protonmail:/root -p 127.0.0.1:1993:993/tcp -p 127.0.0.1:1465:465/tcp --restart=unless-stopped ghcr.io/bostrot/protonmail-bridge:build
```

If you only need to send mail (e.g. as an email notification service), publish just the SMTP port.

To guarantee that nothing can ever talk to the bridge in the clear, publish only `993`/`465` and set `BRIDGE_TLS_ONLY=true`.

## Kubernetes

If you want to run this image in a Kubernetes environment. You can use the [Helm](https://helm.sh/) chart (https://github.com/k8s-at-home/charts/tree/master/charts/stable/protonmail-bridge) created by [@Eagleman7](https://github.com/Eagleman7). More details can be found in [#23](https://github.com/shenxn/protonmail-bridge-docker/issues/23).

If you don't want to use Helm, you can also reference to the guide ([#6](https://github.com/shenxn/protonmail-bridge-docker/issues/6)) written by [@ghudgins](https://github.com/ghudgins).

## Compatibility

The bridge currently only supports some of the email clients. More details can be found on the official website. I've tested this on a Synology DiskStation and it runs well. However, you may need ssh onto it to run the interactive docker command to add your account. The main reason of using this instead of environment variables is that it seems to be the best way to support two-factor authentication.

## Bridge CLI Guide

The initialization step exposes the bridge CLI so you can do things like switch between combined and split mode, change proxy, etc. The [official guide](https://protonmail.com/support/knowledge-base/bridge-cli-guide/) gives more information on to use the CLI.

## Updates

A scheduled GitHub Actions workflow checks the [Proton Bridge releases](https://github.com/ProtonMail/proton-bridge/releases) once a day. When a new version appears it bumps `VERSION` and `deb/PACKAGE`, commits the change, creates a matching git tag and GitHub release, and triggers both image builds.

To run the check by hand:

```
python3 update-check.py
```

## Build

For anyone who want to build this container on your own (for development or security concerns), here is the guide to do so. First, you need to `cd` into the directory (`deb` or `build`, depending on which type of image you want). Then just run the docker build command

```
docker build --build-arg version=$(cat ../VERSION) .
```

That's it. The `Dockerfile` and bash scripts handle all the downloading, building, and packing. You can also add tags, push to your favorite docker registry, or use `buildx` to build multi architecture images.

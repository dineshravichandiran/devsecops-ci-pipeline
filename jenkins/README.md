# Running the pipeline in Jenkins

`Jenkinsfile` (repository root) is a declarative pipeline that mirrors `.github/workflows/devsecops-pipeline.yml`
stage for stage. This folder contains a throwaway local Jenkins that runs it.

## Run it (about 5 minutes after the images are downloaded)
```bash
cd jenkins
cp .env.example .env        # then set JENKINS_ADMIN_PASSWORD to your own long random value
docker compose up -d --build
open http://localhost:8085  # log in as JENKINS_ADMIN_ID with your password
```
The job `devsecops-ci-pipeline` already exists (created by Configuration as Code). Click **Build with Parameters**,
or trigger it from the command line (a CSRF crumb is needed):
```bash
curl -s -c /tmp/cj -u "admin:$PASSWORD" http://localhost:8085/crumbIssuer/api/json   # note the crumb
```
To read the code from a local checkout instead of GitHub, set `JENKINS_REPO_URL=file:///repo`,
`JENKINS_LOCAL_REPO=/absolute/path/to/this/repo` and `JENKINS_ALLOW_LOCAL_CHECKOUT=true` in `.env`.

## What is where
| File | Purpose |
|---|---|
| `Dockerfile` | `jenkins/jenkins:lts-jdk17` plus the Docker CLI and the plugins in `plugins.txt` |
| `plugins.txt` | the plugin list (configuration-as-code, git, pipeline, timestamper, job-dsl, ...) |
| `casc.yaml` | Jenkins Configuration as Code: local admin from the environment, no sign-up, anonymous read off, one pipeline job |
| `docker-compose.yml` | the container, port **8085** (so it does not clash with other tools on 8080), volumes |
| `.env.example` | the settings; the real `.env` is git-ignored |

## How the scanners run
Jenkins itself only needs the Docker CLI. Every scanner is an official image started with `docker run`:
Gitleaks, Semgrep, OWASP Dependency-Check, Trivy, OWASP ZAP, and a JDK image to package the placeholder WAR.
`--volumes-from <the Jenkins container>` makes the workspace visible to each scanner at the same path
(a plain `-v $WORKSPACE:/src` would point at a path that does not exist on the Docker host).

## Faithful to the Actions workflow, including its gaps
| Stage | In Jenkins |
|---|---|
| Secret scanning (Gitleaks) | **blocks** the build on a finding |
| SAST (Semgrep) | report-only (SARIF) |
| SCA (Dependency-Check) | report-only; needs a free NVD API key, otherwise the stage is marked **UNSTABLE** and no report is produced |
| Build and image | placeholder WAR, then `docker build` |
| Image scan (Trivy) | report-only (`--exit-code 0`) |
| DAST (ZAP baseline) | report-only, a failure is logged and marked UNSTABLE |
| Deploy to staging | **placeholder**, prints a message, main only (or `FORCE_STAGING`) |
| Security policy gate | **placeholder**, prints a message, does not read any scan result |

Making Trivy and ZAP real gates is the next step, and it should be done in both pipelines at once.

## Security trade-offs (read before reusing any of this)
- **Mounting `/var/run/docker.sock` and running as root is equivalent to giving the container root on the Docker host.**
  Anything that can change the pipeline (a pull request, a plugin, a compromised dependency) can start any container.
  That is acceptable for a throwaway local demo and wrong for a shared server. Better options: rootless or isolated build
  agents, a remote Docker daemon with limited access, or Kaniko/BuildKit builders that need no daemon socket.
- The admin password comes from `.env` (git-ignored). Do not reuse a real password, and do not commit `.env`.
- `JENKINS_ALLOW_LOCAL_CHECKOUT=true` disables a Jenkins safety check that blocks checking out local folders. It exists
  only for the local-repo mode.
- The scanner images use the `latest` tag for convenience; a real setup should pin versions or digests.

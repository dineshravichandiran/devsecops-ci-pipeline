# Interview notes: the pipeline in Jenkins

## 60-second pitch
"I had a DevSecOps pipeline in GitHub Actions. To learn Jenkins I wrote the same pipeline as a declarative Jenkinsfile,
stage for stage, and ran it on a local Jenkins that I defined as code: the image, the plugin list, the admin user and the job
all come from files. The scanners run as containers, so Jenkins only needs the Docker CLI. I was deliberately faithful, so the
things that are report-only or placeholders in Actions are report-only or placeholders in Jenkins and are labelled that way.
Running it caught real problems: the first runs failed on a Groovy scoping issue and on my own ZAP script, Dependency-Check
could not run without an NVD key, and Semgrep flagged the Jenkins image I had just written for ending as root."

## What each part does
- `Jenkinsfile`: `options` (timestamps, 90-minute timeout, build discarder, no concurrent builds), a `FORCE_STAGING` parameter,
  a `parallel` stage for the two independent scans, `catchError` for report-only stages, `post { always { archiveArtifacts } }`.
- `jenkins/Dockerfile`: LTS Jenkins plus the Docker CLI; plugins installed from `plugins.txt`.
- `jenkins/casc.yaml`: Jenkins Configuration as Code: local admin from environment variables, no sign-up, anonymous read off, one job.
- `jenkins/docker-compose.yml`: port 8085, the Docker socket, optional local-repo mount.
- `jenkins/scripts/zap-baseline.sh`: runs inside the ZAP container.

## Ten questions I should expect
1. **Declarative vs scripted?** Declarative: a fixed structure that is easier to read and lint. I use a small `script {}` block only where I need logic.
2. **How do the scanners run?** As official images through `docker run`. `--volumes-from <the Jenkins container>` makes the workspace appear at the same path in each scanner. A plain `-v $WORKSPACE:/src` would not work because that path does not exist on the Docker host.
3. **What is Configuration as Code?** Jenkins' own settings (users, security, jobs) described in YAML and applied at start, so a fresh container is identical every time and nothing is clicked together.
4. **What is the biggest risk in this setup?** Mounting `/var/run/docker.sock` and running as root is root on the Docker host. Fine for a local demo, wrong for a shared server; I'd use isolated build agents, rootless builds, or a daemonless builder.
5. **Which stages block and which only report?** Gitleaks blocks. Semgrep, Dependency-Check, Trivy and ZAP report only, exactly as in Actions. Deploy and the gate are placeholders and I say so.
6. **Why not make Trivy a real gate?** It reports 4 HIGH findings, all in a Go library bundled in the base image. A real gate would fail every build until the base image is updated. I documented that instead of forcing it.
7. **What went wrong on the way?** (a) A top-level Groovy variable was not visible inside a function: the container id moved to `env.JC`. (b) My ZAP command lost `$WORKSPACE` inside the container, so ZAP could not find its rules file: I moved it into a script and passed the variable with `-e`. (c) Jenkins refuses local-folder checkouts by default: I added an opt-in setting for local mode only.
8. **Why did Dependency-Check fail?** It needs a free NVD API key to download its vulnerability database. Without one it cannot analyse anything, so the stage is marked UNSTABLE and says so, rather than pretending to pass or breaking the build.
9. **What did the pipeline find in your own code?** Semgrep flagged the Jenkins image for ending as root (fixed, 18 to 17 findings) and 17 mutable GitHub Action tags (open). ZAP reported 8 missing-security-header warnings on the placeholder app.
10. **What would you do next?** Pin scanner images by digest, pin Actions by commit hash, make Trivy and ZAP real gates in both pipelines together once the base image is updated, add real deployment and a policy gate that reads the scan results.

## Limits (say them out loud)
SCA produced no report. The app is a placeholder. Nothing was pushed to GitHub, and the Jenkinsfile was run only on a local Jenkins on Apple Silicon. The Actions workflow itself was not changed or re-run.

## "Have you used Jenkins at work?"
"Not in my day job. I wrote this Jenkinsfile and a Configuration-as-Code Jenkins to learn it, by porting a pipeline I already understood. I ran it, fixed the failures, and I can explain every stage and the trade-offs, including the Docker-socket risk."

# Skill: Add CronJob to amazon-watcher-stack

Workflow for adding a new CronJob to the chart.

## Prerequisites

- Know the job name, schedule, command, and image
- Read existing CronJob template: `charts/amazon-watcher-stack/templates/backend-cronjob.yaml`
- Read `charts/amazon-watcher-stack/values.yaml` for the existing CronJob config

## Step 1 — Add Values Section

Add to the appropriate section in `charts/amazon-watcher-stack/values.yaml`:

```yaml
newjob:
  enabled: true
  schedule: "0 */6 * * *"    # Every 6 hours
  image:
    repository: ghcr.io/maborak-technologies-inc/backend
    tag: "latest"
    pullPolicy: IfNotPresent
  command: ["python", "-m", "cli", "run-task"]
  args: []
  resources:
    requests:
      memory: "128Mi"
      cpu: "50m"
    limits:
      memory: "256Mi"
  concurrencyPolicy: Forbid
  activeDeadlineSeconds: 600
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  env: {}
```

Rules:
- `concurrencyPolicy` is always set (Forbid prevents overlapping runs)
- `activeDeadlineSeconds` prevents stuck jobs
- History limits prevent resource buildup
- Feature-gated with `enabled: true/false`

## Step 2 — Create CronJob Template

Create `charts/amazon-watcher-stack/templates/newjob-cronjob.yaml`:

```yaml
{{- if .Values.newjob.enabled }}
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ include "amazon-watcher-stack.fullname" . }}-newjob
  labels:
    {{- include "amazon-watcher-stack.labels" . | nindent 4 }}
    app.kubernetes.io/component: newjob
spec:
  schedule: {{ .Values.newjob.schedule | quote }}
  concurrencyPolicy: {{ .Values.newjob.concurrencyPolicy }}
  successfulJobsHistoryLimit: {{ .Values.newjob.successfulJobsHistoryLimit }}
  failedJobsHistoryLimit: {{ .Values.newjob.failedJobsHistoryLimit }}
  jobTemplate:
    spec:
      activeDeadlineSeconds: {{ .Values.newjob.activeDeadlineSeconds }}
      template:
        metadata:
          labels:
            {{- include "amazon-watcher-stack.selectorLabels" . | nindent 12 }}
            app.kubernetes.io/component: newjob
        spec:
          serviceAccountName: {{ include "amazon-watcher-stack.serviceAccountName" . }}
          restartPolicy: Never
          securityContext:
            runAsNonRoot: true
            fsGroup: 1000
          containers:
            - name: newjob
              image: "{{ .Values.newjob.image.repository }}:{{ .Values.newjob.image.tag }}"
              imagePullPolicy: {{ .Values.newjob.image.pullPolicy }}
              command:
                {{- toYaml .Values.newjob.command | nindent 16 }}
              {{- if .Values.newjob.args }}
              args:
                {{- toYaml .Values.newjob.args | nindent 16 }}
              {{- end }}
              env:
                {{- range $key, $value := .Values.newjob.env }}
                - name: {{ $key }}
                  value: {{ $value | quote }}
                {{- end }}
              resources:
                {{- toYaml .Values.newjob.resources | nindent 16 }}
              securityContext:
                allowPrivilegeEscalation: false
                readOnlyRootFilesystem: true
                capabilities:
                  drop:
                    - ALL
{{- end }}
```

## Step 3 — Validate

```bash
helm lint charts/amazon-watcher-stack --strict
helm template test charts/amazon-watcher-stack -f charts/amazon-watcher-stack/values.yaml | grep -A30 "kind: CronJob"
```

## Step 4 — Bump Chart Version

In `charts/amazon-watcher-stack/Chart.yaml`, bump the patch version.

## Verification Checklist

- [ ] Values section with `enabled` gate, schedule, resources, limits
- [ ] `concurrencyPolicy` set (Forbid or Replace)
- [ ] `activeDeadlineSeconds` set (prevents stuck jobs)
- [ ] History limits set
- [ ] `restartPolicy: Never` (CronJob convention)
- [ ] Security context: non-root, no privilege escalation, read-only FS
- [ ] Template wrapped in `{{- if .Values.newjob.enabled }}`
- [ ] Schedule expression quoted
- [ ] `helm lint --strict` passes
- [ ] `helm template` renders CronJob correctly
- [ ] Chart version bumped

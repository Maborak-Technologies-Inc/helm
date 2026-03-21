# Skill: Add Service to amazon-watcher-stack

Workflow for adding a new service component to the amazon-watcher-stack chart.

## Prerequisites

- Know the service name, image, port, and whether it needs a canary rollout or simple deployment
- Read `CLAUDE.md` for conventions (Rollouts, not Deployments; env prefixes; computed vars)
- Read `charts/amazon-watcher-stack/values.yaml` for the existing values structure
- Read `charts/amazon-watcher-stack/templates/_helpers.tpl` for existing helpers

## Step 1 — Add Values Section

Add a new top-level section to `charts/amazon-watcher-stack/values.yaml`:

```yaml
# ─── NEW SERVICE ─────────────────────────────────────────────
newservice:
  image:
    repository: ghcr.io/maborak-technologies-inc/newservice
    tag: "latest"
    pullPolicy: IfNotPresent
  replicaCount: 1
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
  port: 8080
  env: {}
  rollout:
    strategy: canary
    canary:
      steps:
        - setWeight: 20
        - pause: { duration: 30s }
        - setWeight: 50
        - pause: { duration: 30s }
        - setWeight: 100
  hpa:
    enabled: false
    minReplicas: 2
    maxReplicas: 5
    targetCPUUtilizationPercentage: 70
```

Rules:
- Follow the naming pattern of existing services (backend, ui, screenshot)
- No secrets in defaults — use empty strings or `required`
- Image uses structured `{ repository, tag, pullPolicy }`
- Resources always have `requests` and `limits.memory`

## Step 2 — Add Template Helpers

Add to `charts/amazon-watcher-stack/templates/_helpers.tpl`:

```yaml
{{/*
New Service environment variables
*/}}
{{- define "amazon-watcher-stack.newservice.env" -}}
{{- range $key, $value := .Values.newservice.env }}
{{- if not (has $key (list "COMPUTED_VAR_1" "COMPUTED_VAR_2")) }}
- name: {{ $key }}
  value: {{ $value | quote }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
New Service env checksum
*/}}
{{- define "amazon-watcher-stack.newservice.envChecksum" -}}
{{ .Values.newservice.env | toJson | sha256sum }}
{{- end -}}
```

Rules:
- Namespace all helpers with `amazon-watcher-stack.newservice.*`
- Env helper skips computed vars (add any that are injected in the template)
- Checksum helper covers the env map

## Step 3 — Create Rollout Template

Create `charts/amazon-watcher-stack/templates/newservice-rollout.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: {{ include "amazon-watcher-stack.fullname" . }}-newservice
  labels:
    {{- include "amazon-watcher-stack.labels" . | nindent 4 }}
    app.kubernetes.io/component: newservice
spec:
  replicas: {{ .Values.newservice.replicaCount }}
  selector:
    matchLabels:
      {{- include "amazon-watcher-stack.selectorLabels" . | nindent 6 }}
      app.kubernetes.io/component: newservice
  template:
    metadata:
      labels:
        {{- include "amazon-watcher-stack.selectorLabels" . | nindent 8 }}
        app.kubernetes.io/component: newservice
      annotations:
        checksum/env: {{ include "amazon-watcher-stack.newservice.envChecksum" . }}
    spec:
      serviceAccountName: {{ include "amazon-watcher-stack.serviceAccountName" . }}
      securityContext:
        runAsNonRoot: true
        fsGroup: 1000
      containers:
        - name: newservice
          image: "{{ .Values.newservice.image.repository }}:{{ .Values.newservice.image.tag }}"
          imagePullPolicy: {{ .Values.newservice.image.pullPolicy }}
          ports:
            - name: http
              containerPort: {{ .Values.newservice.port }}
              protocol: TCP
          env:
            {{- include "amazon-watcher-stack.newservice.env" . | nindent 12 }}
            # Computed env vars injected here
          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 15
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 5
            periodSeconds: 5
          resources:
            {{- toYaml .Values.newservice.resources | nindent 12 }}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
  strategy:
    {{- if eq .Values.newservice.rollout.strategy "canary" }}
    canary:
      steps:
        {{- toYaml .Values.newservice.rollout.canary.steps | nindent 8 }}
    {{- end }}
```

## Step 4 — Create Service Template

Create `charts/amazon-watcher-stack/templates/newservice-service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "amazon-watcher-stack.fullname" . }}-newservice
  labels:
    {{- include "amazon-watcher-stack.labels" . | nindent 4 }}
    app.kubernetes.io/component: newservice
spec:
  type: ClusterIP
  ports:
    - port: {{ .Values.newservice.port }}
      targetPort: http
      protocol: TCP
      name: http
  selector:
    {{- include "amazon-watcher-stack.selectorLabels" . | nindent 4 }}
    app.kubernetes.io/component: newservice
```

## Step 5 — Create NetworkPolicy

Create `charts/amazon-watcher-stack/templates/newservice-networkpolicy.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "amazon-watcher-stack.fullname" . }}-newservice
  labels:
    {{- include "amazon-watcher-stack.labels" . | nindent 4 }}
    app.kubernetes.io/component: newservice
spec:
  podSelector:
    matchLabels:
      {{- include "amazon-watcher-stack.selectorLabels" . | nindent 6 }}
      app.kubernetes.io/component: newservice
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              {{- include "amazon-watcher-stack.selectorLabels" . | nindent 14 }}
              app.kubernetes.io/component: backend
      ports:
        - protocol: TCP
          port: {{ .Values.newservice.port }}
```

## Step 6 — Optional: HPA and PDB

If `global.hpa.enabled` and `newservice.hpa.enabled`:

Create `charts/amazon-watcher-stack/templates/newservice-hpa.yaml` and `newservice-pdb.yaml` following the patterns of existing HPA/PDB templates.

## Step 7 — Validate

```bash
helm lint charts/amazon-watcher-stack --strict
helm template test charts/amazon-watcher-stack -f charts/amazon-watcher-stack/values.yaml
```

## Step 8 — Bump Chart Version

In `charts/amazon-watcher-stack/Chart.yaml`, bump the minor version.

## Verification Checklist

- [ ] Values section added with sensible defaults
- [ ] No secrets in values defaults
- [ ] Helper functions added and namespaced
- [ ] Rollout template created with security context, probes, resources
- [ ] Service template with matching selectors
- [ ] NetworkPolicy restricting ingress
- [ ] HPA/PDB if applicable
- [ ] Env checksum annotation for restart on config change
- [ ] `helm lint --strict` passes
- [ ] `helm template` renders without errors
- [ ] Chart version bumped

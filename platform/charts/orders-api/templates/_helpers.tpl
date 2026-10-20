{{- define "orders-api.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "orders-api.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "orders-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "orders-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "orders-api.labels" -}}
{{ include "orders-api.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cloud-platform-blueprint
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
owner: {{ .Values.owner }}
environment: {{ .Values.environment }}
{{- end -}}

{{- define "orders-api.image" -}}
{{- required "image.tag is required (CI and the promotion workflow set it per environment)" .Values.image.tag | printf "%s:%s" .Values.image.repository -}}
{{- end -}}


{{- define "orders-api.analysisArgs" -}}
- name: namespace
  value: {{ .Release.Namespace }}
- name: service
  value: {{ include "orders-api.fullname" . }}
# Hash of the newest ReplicaSet, so the analysis measures canary pods only.
- name: canary-hash
  valueFrom:
    podTemplateHashValue: Latest
{{- end -}}

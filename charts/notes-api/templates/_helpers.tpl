{{/* Chart name. */}}
{{- define "notes-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Fully qualified app name. */}}
{{- define "notes-api.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/* Chart label value. */}}
{{- define "notes-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Selector labels: stable for the lifetime of the release. */}}
{{- define "notes-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "notes-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Common labels. */}}
{{- define "notes-api.labels" -}}
helm.sh/chart: {{ include "notes-api.chart" . }}
{{ include "notes-api.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: notes
{{- end }}

{{/* ServiceAccount name. */}}
{{- define "notes-api.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "notes-api.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Image reference: digest wins over tag. */}}
{{- define "notes-api.image" -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- end }}
{{- end }}

{{/* Environment shared by the API and the migration Job: config + database Secret reference. */}}
{{- define "notes-api.env" -}}
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
{{- $secret := .Values.database.existingSecret }}
{{- range $env, $key := dict "DB_HOST" .Values.database.secretKeys.host "DB_PORT" .Values.database.secretKeys.port "DB_NAME" .Values.database.secretKeys.name "DB_USER" .Values.database.secretKeys.user "DB_PASSWORD" .Values.database.secretKeys.password }}
- name: {{ $env }}
  valueFrom:
    secretKeyRef:
      name: {{ $secret }}
      key: {{ $key }}
{{- end }}
{{- end }}

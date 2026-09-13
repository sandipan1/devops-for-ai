{{/*
Expand the name of the chart.
*/}}
{{- define "synchat.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Validate that non-development environments do not use the mutable latest tag.
CI supplies the immutable tag when rendering or deploying stage and prod.
*/}}
{{- define "synchat.validateImageTag" -}}
{{- if and (ne .environment "dev") (eq .tag "latest") -}}
{{- fail (printf "%s must use an immutable image tag in %s; received latest" .component .environment) -}}
{{- end -}}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "synchat.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "synchat.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "synchat.labels" -}}
helm.sh/chart: {{ include "synchat.chart" . }}
{{ include "synchat.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "synchat.selectorLabels" -}}
app.kubernetes.io/name: {{ include "synchat.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

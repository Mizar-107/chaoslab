{{/*
Expand the name of the chart.
*/}}
{{- define "microshop.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "microshop.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- printf "%s" $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "microshop.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "microshop.labels" -}}
helm.sh/chart: {{ include "microshop.chart" . }}
{{ include "microshop.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "microshop.selectorLabels" -}}
app.kubernetes.io/name: {{ include "microshop.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the namespace
*/}}
{{- define "microshop.namespace" -}}
{{- default .Values.global.namespace .Release.Namespace }}
{{- end }}

{{/*
Service labels - takes service name as parameter
*/}}
{{- define "microshop.serviceLabels" -}}
app: {{ .service }}
tier: {{ .tier }}
version: v1
{{- end }}

{{/*
Service selector labels
*/}}
{{- define "microshop.serviceSelectorLabels" -}}
app: {{ .service }}
{{- end }}

{{/*
Prometheus annotations
*/}}
{{- define "microshop.prometheusAnnotations" -}}
prometheus.io/scrape: "true"
prometheus.io/port: "{{ .port | default "9090" }}"
prometheus.io/path: "/metrics"
{{- end }}

{{- define "ihatemoney.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- define "ihatemoney.fullname" -}}
{{- include "ihatemoney.name" . }}
{{- end }}
{{- define "ihatemoney.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- define "ihatemoney.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ihatemoney.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
{{- define "ihatemoney.labels" -}}
helm.sh/chart: {{ include "ihatemoney.chart" . }}
{{ include "ihatemoney.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

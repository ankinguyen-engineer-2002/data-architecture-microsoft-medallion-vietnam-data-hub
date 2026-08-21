import type { MetricUnit } from "../contracts/types.js";

export interface MetricDefinition {
  label: string;
  unit: MetricUnit;
  format: "percent1" | "quantity2";
}

export const METRIC_DEFINITIONS: Record<string, MetricDefinition> = {
  forecast_accuracy: {
    label: "Forecast Accuracy",
    unit: "percent",
    format: "percent1",
  },
  weighted_mape: {
    label: "Weighted MAPE",
    unit: "percent",
    format: "percent1",
  },
  signed_bias: {
    label: "Signed Forecast Bias",
    unit: "percent",
    format: "percent1",
  },
  rmse: { label: "RMSE", unit: "quantity", format: "quantity2" },
  process_value_add: {
    label: "Process Value Add",
    unit: "percent",
    format: "percent1",
  },
  actual_demand: {
    label: "Actual Demand",
    unit: "quantity",
    format: "quantity2",
  },
};

export function formatMetricValue(
  metricId: string,
  value: number,
  locale: "en-US" | "vi-VN",
): string {
  const definition = METRIC_DEFINITIONS[metricId];
  if (!definition) {
    throw new Error(`Unknown governed metric: ${metricId}`);
  }

  if (definition.format === "percent1") {
    return new Intl.NumberFormat(locale, {
      style: "percent",
      minimumFractionDigits: 1,
      maximumFractionDigits: 1,
    }).format(value);
  }

  return new Intl.NumberFormat(locale, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value);
}

export function sanitizeLabel(value: string, maxLength = 120): string {
  return value.replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, maxLength);
}

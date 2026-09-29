/// A single selectable value within a PLP filter aggregation.
class AggregationOption {
  const AggregationOption({
    required this.label,
    required this.value,
    required this.count,
  });

  final String label;
  final String value;
  final int count;
}

/// A PLP filter facet built dynamically from the `products.aggregations` field
/// (never hardcoded).
class Aggregation {
  const Aggregation({
    required this.attributeCode,
    required this.label,
    required this.options,
  });

  final String attributeCode;
  final String label;
  final List<AggregationOption> options;
}

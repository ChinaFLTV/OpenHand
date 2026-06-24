String escapeXmlText(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

String escapeXmlAttribute(String value) {
  return escapeXmlText(
    value,
  ).replaceAll('"', '&quot;').replaceAll("'", '&apos;');
}

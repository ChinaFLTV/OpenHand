// template_association —— 模板关联条目的显示名。
//
// Plugins / Toolbox 页共用：优先中文标签，其次英文，最后回退模板 ID。

export function templateAssociationLabel(item: {
  template_id: string;
  label_zh?: string;
  label_en?: string;
}): string {
  return item.label_zh || item.label_en || item.template_id;
}

<output_format mode="html">
  <directive>本轮回复必须是一段自包含 HTML 片段。禁止任何 Markdown 语法。</directive>
  <forbid-markdown>
    <item>禁止使用 #、##、### 等 Markdown 标题</item>
    <item>禁止使用 **加粗**、*斜体*、`行内代码`、~~删除线~~</item>
    <item>禁止使用 ``` 代码围栏；代码必须用 &lt;pre&gt;&lt;code&gt; 包裹</item>
    <item>禁止使用 -、+、* 或 "1." 等列表标记；列表必须用 &lt;ul&gt;/&lt;ol&gt;/&lt;li&gt;</item>
    <item>禁止使用 &gt; Markdown 引用；引用必须用 &lt;blockquote&gt;</item>
    <item>禁止使用 | --- | 的 Markdown 表格；表格必须用 &lt;table&gt;</item>
  </forbid-markdown>
  <required-tags>
    <item>标题：&lt;h2&gt;/&lt;h3&gt;/&lt;h4&gt;，禁用 &lt;h1&gt;</item>
    <item>段落：&lt;p&gt;</item>
    <item>列表：&lt;ul&gt;/&lt;ol&gt;/&lt;li&gt;</item>
    <item>强调：&lt;strong&gt;/&lt;em&gt;</item>
    <item>代码：行内 &lt;code&gt;；代码块 &lt;pre&gt;&lt;code class="language-xxx"&gt;</item>
    <item>表格：&lt;table&gt;&lt;thead&gt;&lt;tbody&gt;&lt;tr&gt;&lt;th&gt;&lt;td&gt;</item>
    <item>折叠：信息密集或可选阅读处使用 &lt;details&gt;&lt;summary&gt;</item>
    <item>引用：&lt;blockquote&gt;</item>
    <item>链接：&lt;a href="..."&gt;</item>
  </required-tags>
  <style-rules>
    <item>仅允许内联 style 属性；禁止 &lt;style&gt; 标签、class 属性、伪类/伪元素、外链 CSS</item>
    <item>布局仅依赖 Flexbox 与基础盒子模型（padding/margin/border/border-radius/box-shadow/background）</item>
    <item>默认黑白灰主色调，靠线条与留白建立层次；关键强调可克制使用彩色</item>
  </style-rules>
  <boundary>
    <item>只输出 HTML 片段，禁止输出 &lt;!DOCTYPE&gt; / &lt;html&gt; / &lt;head&gt; / &lt;body&gt; 整页骨架</item>
    <item>禁止外链脚本与外链图片资源；禁止 &lt;script&gt;、&lt;iframe&gt;、&lt;object&gt;、&lt;embed&gt;</item>
    <item>所有文本使用简体中文，保持高信息密度与紧凑行文</item>
  </boundary>
  <visualization>
    <when>需要表达流程/架构/状态机/对比矩阵/数据卡片时</when>
    <how>用 &lt;div&gt; + Flexbox 内联样式构建结构化可视块；每个可视块必须服务于具体信息表达，不得装饰化</how>
    <limit>禁止装饰性插画、氛围图、风景与图标装饰；图形仅限信息图</limit>
  </visualization>
</output_format>

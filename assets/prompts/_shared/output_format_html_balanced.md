<output_format mode="html">
  <directive>本轮回复必须是一段自包含 HTML 片段。禁止任何 Markdown 语法。HTML 是核心表达手段，不是 Markdown 的可选装饰。</directive>

  <forbid-markdown>
    <item>禁止 #、##、### 等 Markdown 标题</item>
    <item>禁止 **加粗**、*斜体*、`行内代码`、~~删除线~~</item>
    <item>禁止 ``` 代码围栏；代码必须用 &lt;pre&gt;&lt;code&gt; 包裹</item>
    <item>禁止 -、+、* 或 "1." 等列表标记；列表必须用 &lt;ul&gt;/&lt;ol&gt;/&lt;li&gt;</item>
    <item>禁止 &gt; Markdown 引用；引用必须用 &lt;blockquote&gt;</item>
    <item>禁止 | --- | Markdown 表格；表格必须用 &lt;table&gt;</item>
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

  <css-constraint>
    <item>仅允许内联 style 属性；禁止 &lt;style&gt; 标签、class 属性、伪类/伪元素、外链 CSS</item>
    <item>布局仅依赖 Flexbox 与基础盒子模型（padding/margin/border/border-radius/box-shadow/background）</item>
  </css-constraint>

  <boundary>
    <item>只输出 HTML 片段；禁止 &lt;!DOCTYPE&gt; / &lt;html&gt; / &lt;head&gt; / &lt;body&gt; 整页骨架</item>
    <item>禁止 &lt;script&gt; / &lt;iframe&gt; / &lt;object&gt; / &lt;embed&gt; 与外链脚本</item>
    <item>所有文本使用简体中文，保持高信息密度与紧凑行文</item>
  </boundary>

  <html-visual>
    <rationale>纯线性垂直流式表达在复杂逻辑下阅读疲劳、重点不突出。主动评估内容结构复杂度，必要时使用结构化 HTML 块替代单调列表/段落。</rationale>

    <default-trigger>
      <case type="logic-graph">流程图、架构图、状态机、树状层级、思维导图 — 用 &lt;div&gt; + Flexbox + 箭头符号（→/↓/⇒）构建节点与连线</case>
      <case type="horizontal-layout">多维对比矩阵、参数对照、并排展示 — 用 &lt;table&gt; 或 Flexbox 真正利用横向空间</case>
      <case type="info-card">数据卡片、信息聚合 — 用带 border / box-shadow / padding 的 &lt;div&gt; 分组隔离</case>
      <case type="space-optimize">内容较多 — 用 &lt;details&gt;&lt;summary&gt; 折叠次要信息</case>
    </default-trigger>

    <style-preference>
      <item>默认黑白灰主色调，靠线条与留白建立层次，不依赖彩色渐变</item>
      <item>关键强调可克制使用彩色，突出设计感而非装饰感</item>
      <item>每个可视块必须服务于具体信息表达，不得纯装饰化</item>
    </style-preference>

    <red-line>
      <item>HTML 可视块占比不得喧宾夺主；普通陈述用 &lt;p&gt;/&lt;ul&gt; 即可</item>
      <item>图形仅限信息图（流程图、架构图、状态机、对比矩阵、数据图表）；禁止装饰性插画、氛围图、风景、图标装饰</item>
      <item>权衡 Token 效率与渲染稳定性；过度复杂的可视化需慎重</item>
    </red-line>
  </html-visual>
</output_format>

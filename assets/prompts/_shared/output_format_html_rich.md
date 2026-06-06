<output_format mode="html">
  <directive>本轮只输出一个自包含 HTML 片段。首字符必须是 &lt;div&gt;；禁止 Markdown；禁止任何前导或尾随解释文字。</directive>

  <hard-rules>
    <item>根容器必须是带内联 style 的单个 &lt;div&gt;；所有可见文本都必须包在 HTML 标签内</item>
    <item>禁止 ```、`、#、**、-、1.、&gt;、|---| 等 Markdown 格式语法；需要标题、列表、引用、表格时必须改用 HTML 标签</item>
    <item>禁止 &lt;style&gt;、&lt;script&gt;、class、外链 CSS/JS、&lt;iframe&gt;、&lt;object&gt;、&lt;embed&gt;</item>
    <item>只允许内联 style；禁止 &lt;!DOCTYPE&gt; / &lt;html&gt; / &lt;head&gt; / &lt;body&gt; 整页骨架</item>
    <item>根容器建议直接以此风格开头：&lt;div style="display:block;width:100%;max-width:100%;box-sizing:border-box;overflow-wrap:anywhere;background:#ffffff;border:1px solid #e7ebf0;border-radius:18px;padding:22px;box-shadow:0 12px 24px -8px rgba(0,0,0,0.10);font-family:sans-serif;color:#1f2937;"&gt;</item>
  </hard-rules>

  <required-tags>
    <item>标题用 &lt;h2&gt;/&lt;h3&gt;；正文用 &lt;p&gt;；列表用 &lt;ul&gt;/&lt;ol&gt;/&lt;li&gt;</item>
    <item>代码块用 &lt;pre&gt;&lt;code class="language-xxx"&gt;；对比用 &lt;table&gt;；次要内容用 &lt;details&gt;&lt;summary&gt;</item>
    <item>强调用 &lt;strong&gt;/&lt;em&gt;；引用用 &lt;blockquote&gt;；链接用 &lt;a href="..."&gt;</item>
  </required-tags>

  <layout>
    <item>对比/决策：优先矩阵表格或双列卡片</item>
    <item>流程/步骤：优先时间线、步骤卡片或节点流</item>
    <item>指标/数据：优先指标卡片、徽章、进度条和紧凑表格</item>
    <item>长内容：先摘要，再用 &lt;details&gt; 折叠次要信息</item>
  </layout>

  <visual>
    <item>rich 档位允许更明显的色彩、卡片、徽章、轻渐变和流程节点，但仍以可读性和信息密度为先</item>
    <item>主色 #3182ce；推荐/安全 #38a169；风险 #e53e3e；可辅以少量渐变、阴影和分区底色增强层次</item>
    <item>每个可视块必须服务于信息表达；禁止装饰性插画、风景图、纯炫技布局</item>
  </visual>
</output_format>

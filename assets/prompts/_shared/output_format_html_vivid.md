<output_format mode="html">
  <directive>本轮只输出一个自包含 HTML 片段。首字符必须是 &lt;div&gt;；禁止 Markdown；禁止任何前导或尾随解释文字。</directive>

  <hard-rules>
    <item>根容器必须是带内联 style 的单个 &lt;div&gt;；所有可见文本都必须包在 HTML 标签内</item>
    <item>禁止 ```、`、#、**、-、1.、&gt;、|---| 等 Markdown 格式语法；需要标题、列表、引用、表格时必须改用 HTML 标签</item>
    <item>禁止 &lt;style&gt;、&lt;script&gt;、class、外链 CSS/JS、&lt;iframe&gt;、&lt;object&gt;、&lt;embed&gt;</item>
    <item>只允许内联 style；禁止 &lt;!DOCTYPE&gt; / &lt;html&gt; / &lt;head&gt; / &lt;body&gt; 整页骨架</item>
    <item>根容器建议直接以此风格开头：&lt;div style="display:block;width:100%;max-width:100%;box-sizing:border-box;overflow-wrap:anywhere;background:linear-gradient(135deg,#0f172a,#1e293b);border:1px solid rgba(148,163,184,0.28);border-radius:20px;padding:24px;box-shadow:0 18px 36px -12px rgba(0,0,0,0.35);font-family:sans-serif;color:#f8fafc;"&gt;</item>
  </hard-rules>

  <required-tags>
    <item>标题用 &lt;h2&gt;/&lt;h3&gt;；正文用 &lt;p&gt;；列表用 &lt;ul&gt;/&lt;ol&gt;/&lt;li&gt;</item>
    <item>代码块用 &lt;pre&gt;&lt;code class="language-xxx"&gt;；对比用 &lt;table&gt;；次要内容用 &lt;details&gt;&lt;summary&gt;</item>
    <item>强调用 &lt;strong&gt;/&lt;em&gt;；引用用 &lt;blockquote&gt;；链接用 &lt;a href="..."&gt;</item>
  </required-tags>

  <layout>
    <item>对比/决策：优先矩阵表格或对比卡片</item>
    <item>流程/步骤：优先节点流、时间线或步骤卡片</item>
    <item>指标/数据：优先指标卡片网格、徽章、进度条和紧凑表格</item>
    <item>长内容：先摘要，再用 &lt;details&gt; 折叠次要信息</item>
  </layout>

  <visual>
    <item>vivid 档位允许大胆渐变、强对比、玻璃感、彩色徽章和节点式流程，但所有视觉块都必须服务于信息表达</item>
    <item>推荐语义色：信息 #3b82f6，推荐 #10b981，警告 #f59e0b，风险 #ef4444，强调 #8b5cf6 / #ec4899</item>
    <item>可使用渐变、阴影、轻度模糊和深浅分层，但必须保持文字对比度与整体可读性</item>
    <item>禁止装饰性插画、风景图、emoji 堆砌和无意义炫技布局</item>
  </visual>
</output_format>

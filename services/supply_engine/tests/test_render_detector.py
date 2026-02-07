from app.http.render_detector import needs_browser_render


def test_detects_js_shell_html():
    html = """
    <html>
      <head><title>Store</title></head>
      <body>
        <div id="__next"></div>
        <noscript>Please enable JavaScript to continue.</noscript>
        <script src="/_next/static/chunks/main.js"></script>
      </body>
    </html>
    """
    assert needs_browser_render(html) is True


def test_does_not_flag_server_rendered_product_page():
    html = """
    <html>
      <head>
        <meta property="og:title" content="Server Rendered Sofa" />
        <meta property="product:price:amount" content="12990" />
      </head>
      <body>
        <main>
          <h1>Server Rendered Sofa</h1>
          <p>Solid oak frame, bouclé upholstery.</p>
        </main>
      </body>
    </html>
    """
    assert needs_browser_render(html) is False

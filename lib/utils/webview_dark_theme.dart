/// Shared dark-mode injection for site WebViews (login + user center).
class WebViewDarkTheme {
  WebViewDarkTheme._();

  static const ColorValue darkBgArgb = 0xFF1C1B1F;
  static const ColorValue lightBgArgb = 0xFFFFFBFE;

  /// ES5-only injector: CSS overrides + light-node painter + MutationObserver.
  static const String injectJs = r'''
(function(){
  try {
    var STYLE_ID = 'xianbao-app-dark-style';
    var css = ''
      + 'html,body{background:#1C1B1F !important;background-color:#1C1B1F !important;color:#E6E1E5 !important;}'
      + 'html{color-scheme:dark !important;}'
      + '*,*::before,*::after{border-color:#49454F !important;box-shadow:none !important;}'
      + 'body,div,section,article,main,aside,header,footer,nav,ul,ol,li,table,thead,tbody,tr,td,th,'
      + 'p,span,label,h1,h2,h3,h4,h5,h6,form,fieldset,legend,dl,dt,dd,a{'
      + 'color:#E6E1E5 !important;}'
      + 'a,a:link,a:visited,a:hover{color:#FFB4AB !important;}'
      /* layui admin / user center */
      + '.layui-layout-admin,.layui-layout-body,#LAY_app,#LAY_app_body,.layadmin-tabsbody-item,'
      + '.layui-body,.layui-side,.layui-side-scroll,.layui-header,.layui-footer,.layui-fluid,'
      + '.layui-container,.layui-row,[class*="layui-col-"],.layui-card,.layui-card-header,'
      + '.layui-card-body,.layui-panel,.layui-tab,.layui-tab-content,.layui-tab-title,'
      + '.layui-form,.layui-table,.layui-table-view,.layui-table-box,.layui-table-header,'
      + '.layui-table-body,.layui-table-tool,.layui-elem-quote,.layui-bg-white,.layui-bg-gray,'
      + '.layadmin-pagetabs,.layui-show,.layui-layer-content,.layui-layer,.layui-m-layer,'
      + '.mochu,.ucenter,.content,.main,.box,.wrapper,.container,.panel,.card{'
      + 'background:#141218 !important;background-color:#141218 !important;color:#E6E1E5 !important;}'
      + '.layui-layout-admin .layui-header,.layui-bg-black,.layui-nav-tree{'
      + 'background:#141218 !important;background-color:#141218 !important;}'
      + '.layui-nav .layui-nav-item a,.layui-nav-tree .layui-nav-item a,'
      + '.layui-nav-tree .layui-nav-child a{color:#E6E1E5 !important;background:transparent !important;}'
      + '.layui-nav-tree .layui-this,.layui-nav-tree .layui-this>a,'
      + '.layui-nav-tree .layui-nav-child dd.layui-this,'
      + '.layui-nav-tree .layui-nav-child dd.layui-this a,'
      + '.layui-this,.layui-this>a{background:#8C1D18 !important;background-color:#8C1D18 !important;color:#FFDAD6 !important;}'
      /* login page (layadmin-user-login) */
      + '#LAY-user-login,.layadmin-user-login,.layadmin-user-login-main,'
      + '.layadmin-user-login-box,.layadmin-user-login-header,.layadmin-user-login-body,'
      + '#loginretbody,#wechathtml,.login-tip,.login-tipdiv,.poptip,.poptip-content,'
      + '.poptip-arrow,.layadmin-user-display-show{'
      + 'background:#1C1B1F !important;background-color:#1C1B1F !important;background-image:none !important;color:#E6E1E5 !important;}'
      + '.layadmin-user-login-main:before,#loginretbody:before,.layadmin-user-login:before{'
      + 'background:none !important;background-image:none !important;opacity:0 !important;content:none !important;}'
      + '.layadmin-user-login-header h2,.layadmin-user-login-header h3,.layadmin-user-login-header p,'
      + '.poptip-content,.login-tip,.layadmin-user-jump-change,.layadmin-link{color:#E6E1E5 !important;}'
      + '.layadmin-user-login-icon,.layui-icon.poptip-i{color:#CAC4D0 !important;}'
      + 'input,textarea,select,button,.layui-input,.layui-textarea,.layui-select,'
      + '.layui-form-select,.layui-form-select dl,.layui-form-select dl dd,'
      + '.layui-btn,.layui-btn-primary,.layui-btn-normal,'
      + '#username,#password,#vercode{'
      + 'background:#2B2930 !important;background-color:#2B2930 !important;color:#E6E1E5 !important;border-color:#49454F !important;}'
      + '.layui-btn-normal,.layui-btn-danger,.layui-btn-fluid,'
      + 'button[lay-filter],.layui-btn-primary.layui-btn-fluid{background:#8C1D18 !important;color:#FFDAD6 !important;}'
      + '.layui-table td,.layui-table th,.layui-table-cell{background:#1C1B1F !important;color:#E6E1E5 !important;border-color:#49454F !important;}'
      + '.layui-table thead tr,.layui-table-header,.layui-table thead{background:#2B2930 !important;}'
      + '.layui-icon,.iconfont{color:#E6E1E5 !important;}'
      + 'img{opacity:0.95 !important;}'
      + 'img.layadmin-user-login-codeimg,#captcha_img{opacity:1 !important;background:#fff !important;}'
      + 'canvas,svg{background:transparent !important;}';

    function isLightBg(rgb) {
      if (!rgb || rgb === 'transparent') return false;
      var m = rgb.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([0-9.]+))?/);
      if (!m) return false;
      var a = m[4] === undefined ? 1 : parseFloat(m[4]);
      if (a < 0.15) return false;
      var r = parseInt(m[1], 10), g = parseInt(m[2], 10), b = parseInt(m[3], 10);
      var L = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      return L >= 180;
    }

    function isDarkText(rgb) {
      if (!rgb) return false;
      var m = rgb.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
      if (!m) return false;
      var L = 0.2126 * parseInt(m[1],10) + 0.7152 * parseInt(m[2],10) + 0.0722 * parseInt(m[3],10);
      return L <= 90;
    }

    function paintLightNodes() {
      var nodes = document.querySelectorAll(
        'html,body,div,section,main,aside,header,footer,nav,ul,ol,li,table,thead,tbody,tr,td,th,article,form,fieldset,p,span,a,label,h1,h2,h3,h4,h5,h6,input,textarea,button'
      );
      for (var i = 0; i < nodes.length; i++) {
        var el = nodes[i];
        try {
          var tag = (el.tagName || '').toLowerCase();
          if (tag === 'img' || tag === 'video' || tag === 'canvas' || tag === 'svg' || tag === 'path') continue;
          var st = window.getComputedStyle(el);
          if (isLightBg(st.backgroundColor)) {
            el.style.setProperty('background-color', '#1C1B1F', 'important');
            el.style.setProperty('background-image', 'none', 'important');
            el.style.setProperty('background', '#1C1B1F', 'important');
          }
          if (tag !== 'input' && tag !== 'textarea' && isDarkText(st.color)) {
            el.style.setProperty('color', '#E6E1E5', 'important');
          }
        } catch (e) {}
      }
    }

    function inject() {
      var parent = document.head || document.documentElement;
      var s = document.getElementById(STYLE_ID);
      if (!s) {
        s = document.createElement('style');
        s.id = STYLE_ID;
        s.type = 'text/css';
        parent.appendChild(s);
      }
      if (s.styleSheet) { s.styleSheet.cssText = css; } else { s.innerHTML = css; }
      try {
        document.documentElement.style.setProperty('background', '#1C1B1F', 'important');
        document.documentElement.style.setProperty('background-color', '#1C1B1F', 'important');
        document.documentElement.style.setProperty('color', '#E6E1E5', 'important');
        if (document.body) {
          document.body.style.setProperty('background', '#1C1B1F', 'important');
          document.body.style.setProperty('background-color', '#1C1B1F', 'important');
          document.body.style.setProperty('color', '#E6E1E5', 'important');
        }
      } catch (e) {}
      paintLightNodes();
      return true;
    }

    inject();

    if (!window.__xianbaoDarkObs) {
      var t = null;
      window.__xianbaoDarkObs = new MutationObserver(function () {
        if (t) return;
        t = setTimeout(function () {
          t = null;
          if (!document.getElementById(STYLE_ID)) inject();
          else paintLightNodes();
        }, 120);
      });
      try {
        window.__xianbaoDarkObs.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['style', 'class']
        });
      } catch (e) {}
    }

    if (!window.__xianbaoDarkKeepAlive) {
      window.__xianbaoDarkKeepAlive = setInterval(function () {
        if (!document.getElementById(STYLE_ID)) inject();
      }, 1500);
    }
    return 'dark-ok';
  } catch (err) {
    return 'dark-err:' + (err && err.message ? err.message : err);
  }
})();
''';

  static const String removeJs = r'''
(function(){
  try {
    var s = document.getElementById('xianbao-app-dark-style');
    if (s && s.parentNode) s.parentNode.removeChild(s);
    if (window.__xianbaoDarkObs) {
      try { window.__xianbaoDarkObs.disconnect(); } catch (e) {}
      window.__xianbaoDarkObs = null;
    }
    if (window.__xianbaoDarkKeepAlive) {
      clearInterval(window.__xianbaoDarkKeepAlive);
      window.__xianbaoDarkKeepAlive = null;
    }
    return 'light-ok';
  } catch (err) {
    return 'light-err';
  }
})();
''';
}

/// Color int helper without importing Flutter in pure-const script file.
/// Actual Color is constructed by callers.
typedef ColorValue = int;

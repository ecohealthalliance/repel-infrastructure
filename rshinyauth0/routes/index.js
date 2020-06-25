var express = require('express');
var passport = require('passport');
var httpProxy = require('http-proxy');
var ensureLoggedIn = require('connect-ensure-login').ensureLoggedIn();
var router = express.Router();

var env = process.env;

// This adds support for the current way to sso
var authenticateWithDefaultPrompt = passport.authenticate('auth0', {});
var authenticateWithPromptNone = passport.authenticate('auth0', {
  prompt: 'none'
});

router.get('/login',
  function (req, res, next) {
    if (env.CHECK_SESSION === 'true' && req.query.sso !== 'false') {
      return authenticateWithPromptNone(req, res, next);
    }
    return authenticateWithDefaultPrompt(req, res, next);
  },
  function (req, res) {
    res.redirect('/reports/');
  });

router.get('/logout', function(req, res){
  var logoutUrl = env.LOGOUT_URL;

  if (env.LOGOUT_AUTH0 === 'true') {
    logoutUrl = 'https://' + env.AUTH0_DOMAIN + '/v2/logout?returnTo='
      + env.LOGOUT_URL + '&client_id=' + env.AUTH0_CLIENT_ID
      + (env.LOGOUT_FEDERATED === 'true'? '&federated' : '');
  }

  req.logout();
  res.redirect(logoutUrl);
});

router.get('/callback',
  function (req, res, next) {
    passport.authenticate('auth0', function (err, user, info) {
      if (err) {
        next(err);
      }

      if (info === 'login_required') {
        return res.redirect('/login?sso=false');
      }

      if (user) {
        return req.login(user, function (err) {
          if (err) {
            next(err);
          }
          res.redirect(req.session.returnTo || '/reports/');
        });
      }

      next(new Error(info));
    })(req, res, next);
  });

var proxy = httpProxy.createProxyServer({
  target: {
      host: process.env.SHINY_HOST,
      port: process.env.SHINY_PORT
    }
});

proxy.on('error', function(e) {
  console.log('Error connecting');
  console.log(e);
});

var setIfExists = function(proxyReq, header, value){
  if(value){
    proxyReq.setHeader(header, value);
  }
};

proxy.on('proxyReq', function(proxyReq, req, res, options) {
  setIfExists(proxyReq, 'x-auth0-nickname', req.user._json.nickname);
  setIfExists(proxyReq, 'x-auth0-user_id', req.user._json.user_id);
  setIfExists(proxyReq, 'x-auth0-email', req.user._json.email);
  setIfExists(proxyReq, 'x-auth0-name', req.user._json.name);
  setIfExists(proxyReq, 'x-auth0-picture', req.user._json.picture);
  setIfExists(proxyReq, 'x-auth0-locale', req.user._json.locale);
});

/* Proxy all requests */
router.all(/.*/, ensureLoggedIn, function(req, res, next) {
  proxy.web(req, res);
});

module.exports = router;

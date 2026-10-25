// The small scripts a filter list asks a page to run.
//
// Half of blocking adverts is refusing a request. The other half is the site's
// own check for whether one was refused: a script that builds a bait element,
// looks for an advert vendor's global, or fetches a URL that only a blocker
// would have stopped — and then covers the article until the blocker is
// turned off. Those checks are scripts too, and a script can be shown what it
// wants to see.
//
// The list says which of these to run and where (`##+js(name, arg, …)`), and
// Tools/filters.py turns that into Resources/Shield/scriptlets.json. This file
// is the running half: named routines, each given the arguments the list wrote.
// It is injected at the start of the document, in the page's own world, before
// the page's first script runs — the only moment early enough to stand between
// a check and what it is checking.
//
// Written here rather than picked up from a blocker's own source: the names and
// the argument shapes are the filter lists', the code is Aura's. Nothing in
// here reaches the network or writes anything down.

(function () {
    'use strict';

    let rules;
    try {
        rules = window.__auraScriptlets;
        delete window.__auraScriptlets;
    } catch (error) {
        return;
    }
    if (!Array.isArray(rules)) { return; }

    // MARK: - what a list means by a site

    // A rule names sites, and the page's own host decides whether it is for
    // this document. `example.com` is the site and everything under it,
    // `*.example.*` is what a list writes when it does not know the ending,
    // and a leading `~` is a site the rule is not for.
    function forHost(sites, host) {
        if (!Array.isArray(sites) || sites.length === 0) { return true; }
        let named = false;
        let refused = false;
        for (const entry of sites) {
            const negative = entry.charAt(0) === '~';
            const pattern = negative ? entry.slice(1) : entry;
            if (!pattern) { continue; }
            let matched;
            if (pattern.indexOf('*') !== -1) {
                const source = pattern
                    .split('*')
                    .map(function (piece) { return piece.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); })
                    .join('.*');
                try {
                    matched = new RegExp('(^|\\.)' + source + '$').test(host);
                } catch (error) {
                    matched = false;
                }
            } else {
                matched = host === pattern || host.endsWith('.' + pattern);
            }
            if (matched) {
                if (negative) { refused = true; } else { named = true; }
            }
        }
        return named && !refused;
    }

    // MARK: - the little that is shared

    function isExpression(text) {
        return text.length > 2 && text.charAt(0) === '/' && text.charAt(text.length - 1) === '/';
    }

    // An argument is either the text to look for or, written between slashes,
    // a regular expression of it.
    function says(text, needle) {
        if (!needle) { return true; }
        text = String(text || '');
        if (!isExpression(needle)) { return text.indexOf(needle) !== -1; }
        try {
            return new RegExp(needle.slice(1, -1)).test(text);
        } catch (error) {
            return false;
        }
    }

    // What a list's argument means as a value: the words a script compares
    // against, and the two functions the lists use to neuter a callback.
    function valueOf(raw) {
        if (raw === undefined) { return undefined; }
        if (raw === 'true') { return true; }
        if (raw === 'false') { return false; }
        if (raw === 'null') { return null; }
        if (raw === 'undefined') { return undefined; }
        if (raw === 'noopFunc') { return function () { }; }
        if (raw === 'trueFunc') { return function () { return true; }; }
        if (raw === 'falseFunc') { return function () { return false; }; }
        if (raw === '{}') { return {}; }
        if (raw === '[]') { return []; }
        if (raw === '""') { return ''; }
        if (/^-?\d+(\.\d+)?$/.test(raw)) { return Number(raw); }
        return raw;
    }

    // `navigator.globalPrivacyControl`, `Navigator.prototype.globalPrivacyControl`,
    // `gnt.x.adm`: the object a property hangs off, and the property. The
    // parts in between are made if the page has not made them yet, because a
    // check that reaches for `ncbi.sg.ping` must find something there.
    function place(path, create) {
        const parts = String(path).split('.').filter(Boolean);
        if (parts.length === 0) { return null; }
        let owner = window;
        for (let index = 0; index < parts.length - 1; index += 1) {
            const part = parts[index];
            let next = owner[part];
            if (next === undefined || next === null) {
                if (!create) { return null; }
                try {
                    next = {};
                    owner[part] = next;
                } catch (error) {
                    return null;
                }
            }
            owner = next;
        }
        return { owner: owner, key: parts[parts.length - 1] };
    }

    function read(where) {
        try {
            return where.owner[where.key];
        } catch (error) {
            return undefined;
        }
    }

    function replace(where, get, set) {
        try {
            Object.defineProperty(where.owner, where.key, {
                configurable: true,
                enumerable: true,
                get: get,
                set: set || function () { },
            });
            return true;
        } catch (error) {
            return false;
        }
    }

    // A page that replaces what was patched would get its check back, so
    // anything defined on a global is defined again once the document is
    // parsed and again when everything has loaded.
    function again(apply) {
        const once = function () {
            try { apply(); } catch (error) { }
        };
        document.addEventListener('DOMContentLoaded', once, true);
        window.addEventListener('load', once, true);
    }

    // MARK: - the scripts

    const scripts = {};

    // A property that reads as the value the list wants, whatever the page
    // does with it. This is the one that answers "is an ad blocker here?" with
    // the answer the site wants to hear.
    scripts['set-constant'] = function (args) {
        const path = args[0];
        if (!path) { return; }
        const wanted = valueOf(args[1]);
        const apply = function () {
            const where = place(path, true);
            if (!where) { return; }
            replace(where, function () { return wanted; });
        };
        apply();
        again(apply);
    };

    // The property still reads as it did, unless the script reaching for it is
    // the one that checks for a blocker: then the read throws, and the check
    // takes its own script down with it instead of the page.
    scripts['abort-current-script'] = function (args) {
        const path = args[0];
        const needle = args[1];
        const where = place(path, true);
        if (!where) { return; }
        let saved = read(where);
        replace(where, function () {
            const script = document.currentScript;
            if (!script) { return saved; }
            if (!needle) { throw new ReferenceError(''); }
            if (says(script.textContent, needle) || says(script.src, needle)) {
                throw new ReferenceError('');
            }
            return saved;
        }, function (value) { saved = value; });
    };

    // The same, for a check that is not the script reaching for the property
    // but something it called: the stack is what is looked at.
    scripts['abort-on-stack-trace'] = function (args) {
        const path = args[0];
        const needle = args[1];
        const where = place(path, true);
        if (!where) { return; }
        let saved = read(where);
        replace(where, function () {
            const stack = new Error().stack || '';
            if (!needle || says(stack, needle)) { throw new ReferenceError(''); }
            return saved;
        }, function (value) { saved = value; });
    };

    // A listener the list knows by name never gets added: the click a page
    // logs is the one it registered, and it is not this.
    scripts['addEventListener-defuser'] = function (args) {
        const type = args[0];
        const needle = args[1];
        const add = EventTarget.prototype.addEventListener;
        if (!add) { return; }
        EventTarget.prototype.addEventListener = function (kind, listener, options) {
            try {
                if (!type || kind === type) {
                    if (!needle) { return; }
                    if (says(String(listener), needle)) { return; }
                }
            } catch (error) { }
            return add.call(this, kind, listener, options);
        };
    };

    // A script element carrying a string the page later looks for is taken
    // out before anything looks for it.
    scripts['remove-node-text'] = function (args) {
        const name = String(args[0] || 'script').toLowerCase();
        const needle = args[1];
        if (!needle) { return; }
        const sweep = function (root) {
            try {
                const found = root.querySelectorAll(name);
                for (const element of found) {
                    if (says(element.textContent, needle)) { element.remove(); }
                }
            } catch (error) { }
        };
        const watch = function () {
            try {
                new MutationObserver(function (records) {
                    for (const record of records) {
                        for (const node of record.addedNodes) {
                            if (node.nodeType !== 1) { continue; }
                            if (says(node.textContent, needle) &&
                                (node.tagName.toLowerCase() === name ||
                                 node.querySelector(name))) {
                                sweep(node);
                                if (node.tagName.toLowerCase() === name) { node.remove(); }
                            }
                        }
                    }
                }).observe(document, { childList: true, subtree: true });
            } catch (error) { }
        };
        sweep(document);
        watch();
    };

    // A stored value, written before the page's own script reads it.
    scripts['set-local-storage-item'] = function (args) {
        const key = args[0];
        if (!key) { return; }
        const wanted = args[1];
        const apply = function () {
            try {
                if (wanted === '$remove$') {
                    localStorage.removeItem(key);
                } else {
                    localStorage.setItem(key, wanted === undefined ? '' : String(wanted));
                }
            } catch (error) { }
        };
        apply();
        again(apply);
    };

    // A cookie the page sets for itself, set here instead. A page that reloads
    // until it sees one would reload forever, so it is reloaded once.
    scripts['set-cookie'] = function (args) {
        const name = args[0];
        if (!name) { return; }
        const wanted = args[1] === undefined ? '' : String(args[1]);
        const path = args[2] || '/';
        let reload = false;
        for (const argument of args) {
            if (argument === 'reload') { reload = true; }
        }
        try {
            document.cookie = name + '=' + wanted + '; path=' + path + '; SameSite=Lax';
            if (reload && sessionStorage.getItem('aura-cookie-' + name) !== '1') {
                sessionStorage.setItem('aura-cookie-' + name, '1');
                location.reload();
            }
        } catch (error) { }
    };

    // A cookie the page looks for and should not find: taken away as often as
    // the page puts it back, for a while.
    scripts['cookie-remover'] = function (args) {
        const name = args[0];
        if (!name) { return; }
        const wipe = function () {
            try {
                for (const path of ['/', location.pathname]) {
                    document.cookie = name + '=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=' + path;
                }
            } catch (error) { }
        };
        wipe();
        let left = 10;
        const timer = setInterval(function () {
            wipe();
            left -= 1;
            if (left <= 0) { clearInterval(timer); }
        }, 1000);
    };

    // A request for the URL that only a check makes, answered here with
    // nothing at all, so no request is made and the check sees an answer.
    scripts['no-fetch-if'] = function (args) {
        const needle = args[0];
        const real = window.fetch;
        if (typeof real !== 'function') { return; }
        window.fetch = function (input) {
            try {
                const url = typeof input === 'string' ? input : (input && input.url) || '';
                if (says(url, needle)) {
                    return Promise.resolve(new Response('', {
                        status: 200,
                        headers: { 'content-type': 'text/plain' },
                    }));
                }
            } catch (error) { }
            return real.apply(this, arguments);
        };
    };

    scripts['no-xhr-if'] = function (args) {
        const needle = args[0];
        const xhr = XMLHttpRequest.prototype;
        const open = xhr.open;
        const send = xhr.send;
        if (!open || !send) { return; }
        xhr.open = function (method, url) {
            try {
                this.auraStopped = says(url, needle);
                if (this.auraStopped) {
                    Object.defineProperty(this, 'readyState', { configurable: true, get: function () { return 4; } });
                    Object.defineProperty(this, 'status', { configurable: true, get: function () { return 200; } });
                    Object.defineProperty(this, 'responseText', { configurable: true, get: function () { return ''; } });
                    Object.defineProperty(this, 'response', { configurable: true, get: function () { return ''; } });
                }
            } catch (error) { }
            return open.apply(this, arguments);
        };
        xhr.send = function () {
            if (this.auraStopped) {
                const target = this;
                setTimeout(function () {
                    for (const kind of ['readystatechange', 'load', 'loadend']) {
                        try { target.dispatchEvent(new Event(kind)); } catch (error) { }
                    }
                }, 0);
                return;
            }
            return send.apply(this, arguments);
        };
    };

    // MARK: - running what this document asked for

    const host = (function () {
        try { return String(location.hostname || '').toLowerCase(); } catch (error) { return ''; }
    })();

    for (const rule of rules) {
        if (!rule || !Array.isArray(rule.js)) { continue; }
        if (!forHost(rule.sites, host)) { continue; }
        const run = scripts[rule.js[0]];
        if (typeof run !== 'function') { continue; }
        try {
            run(Array.isArray(rule.js[1]) ? rule.js[1] : []);
        } catch (error) {
            // A scriptlet that cannot run is one this page is left without; it
            // is never a reason for the page to stop loading.
        }
    }
})();

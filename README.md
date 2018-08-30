magit-gerrit2
============

Magit plugin for Gerrit Code Review.

This is a fork of [magit-gerrit](https://github.com/terranpro/magit-gerrit), patched with bug fixes.

Installation
============

If you have a recent Emacs with `package.el`, you can install `magit-gerrit2`
from [MELPA](http://melpa.milkbox.net/).

Otherwise, you'll have to download `magit-gerrit2.el` and ensure it is in
a directory in your `load-path`.

Then:

```
(require 'magit-gerrit2)

;; if remote url is not using the default gerrit port and
;; ssh scheme, need to manually set this variable
(setq-default magit-gerrit2-ssh-creds "myid@gerrithost.org")

;; if necessary, use an alternative remote instead of 'origin'
(setq-default magit2-gerrit-remote "gerrit")  
```


Workflow
============

1. Check out branch, make changes, and commit...
2. Gerrit Push Commit for Code Review => R P
3. Gerrit Add Reviewer => R A (optional)
4. Wait for code review and verification (approvals updated in magit-status)
5. Gerrit Submit Review => R S


Magit Gerrit Configuration
============

For simple setups, it should be enough to set the default value for 
`magit-gerrit2-ssh-creds` and `magit-gerrit2-remote` as shown above.

For per project configurations, consider using buffer local or directory local
variables.


`/home/dev/code/prj1/.dir-locals.el`:

```
((magit-mode .
      ((magit-gerrit2-ssh-creds . "dev_a@prj1.server.com")
       (magit-gerrit2-remote . "gerrit"))))
```

Author
============

Brian Fransioli  ( assem@terranpro.org )


Acknowledgements
============

Thanks for using and improving magit-gerrit2!  Enjoy!

Please help improve magit-gerrit2!  Pull requests welcomed!

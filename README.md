# image-triage.el

image-triage is a package for quickly looking through large
collections of images.

It needs [exiftool](https://exiftool.org/) and ImageMagick's
`convert` to work.  In addition, the `jpgpreview` binary (source
included in this package) should be compiled to speed things up
greatly.

## Building

```
make            # builds jpgpreview and generates image-triage-autoloads.el
make jpgpreview # build the helper binary only
make autoloads  # generate autoloads only
```

## With use-package

From a local checkout (the `:commands` keyword defines the autoloads
for you):

```elisp
(use-package image-triage
  :load-path "~/src/image-triage.el/"
  :commands (image-triage-directory image-triage-tree)
  :custom (image-triage-layout 'grid)
  :bind (("C-c i" . image-triage-directory)
         ("C-c I" . image-triage-tree)))
```

Installed from a package archive (MELPA/NonGNU ELPA), with
`package-vc-install`, or with `straight.el`, autoloads are generated
automatically, so this is enough:

```elisp
(use-package image-triage
  :commands (image-triage-directory image-triage-tree)
  :custom ((image-triage-layout 'list)
           (image-triage-thumbnail-height 120))
  :bind (("C-c i" . image-triage-directory)
         ("C-c I" . image-triage-tree)))
```

With `package-vc`:

```elisp
(use-package image-triage
  :vc (:url "https://github.com/larsmagne/image-triage.el" :rev :newest)
  :commands (image-triage-directory image-triage-tree))
```

With `straight.el`:

```elisp
(use-package image-triage
  :straight (:type git :host github :repo "larsmagne/image-triage.el")
  :commands (image-triage-directory image-triage-tree))
```

### The jpgpreview helper

`jpgpreview` is looked for next to `image-triage.el` first, and then
in `exec-path`.  If it lives somewhere else, point
`image-triage-jpgpreview-program` at it.  You can also build it from
Emacs after loading the package:

```elisp
(use-package image-triage
  :commands (image-triage-directory image-triage-tree)
  :config (image-triage-compile-jpgpreview))
```

## Customizable options

All user options live in the `image-triage` customization group
(`M-x customize-group RET image-triage`) and can be set from
`use-package` with `:custom`:

* `image-triage-file-name-regexps` — which files count as images.
* `image-triage-layout` — `grid` or `list`.
* `image-triage-thumbnail-height`, `image-triage-thumbnail-width` —
  thumbnail sizes.
* `image-triage-preview-height` — full preview size.
* `image-triage-jpgpreview-program` — location of the helper binary.

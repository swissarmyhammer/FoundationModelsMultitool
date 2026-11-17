---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffff8780
title: 'Public API: list the files of a folder that .gitignore does not ignore'
---
Request of testudoapp-75 (Files view of TestudoApp 94bf2b5, State/FolderListing.swift). The view lists node_modules and .build, because FileManager does not apply .gitignore.

Make a public API over the internal libgit2 walk of FileWalker:
`FolderFiles.list(in: URL, includeHidden: Bool = false) async -> [String]`.

- Gives the regular files under the folder, as paths relative to it, sorted.
- In a work folder of a repository, it gives the tracked files and the untracked files that the ignore rules do not exclude (libgit2 only, no git child process).
- Outside a repository, it walks the folder with FileManager.
- With includeHidden false, it skips each path that has a component that starts with a dot.
- It never gives a path in a .git folder.

Tests: a repository with an ignored folder, a folder outside a repository, hidden files with and without includeHidden, and a sub folder of a repository.
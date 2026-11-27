# GitLama QML tests

Qt Quick Tests that catch major regressions in the QML: every file in
`qml/GitLama` compiles, the Compass shows running work and its activity wash,
and diffs scroll vertically and sideways. `scripts/verify.py` runs them
offscreen (part of `./scripts/verify.sh` and the Linux CI lane):

    QT_QPA_PLATFORM=offscreen qmltestrunner -import qml -import qml/tests/stubs -input qml/tests

`stubs/GitLamaNative` stands in for the native types the application
registers (`rust-core/desktop/app/src/native`); `tests/package/test_qml_native_stubs.py`
keeps their properties and signals in step with the C++ declarations. Tests
drive components with plain data (the diff model is a JavaScript array with the
calls `DiffView` makes) and assert settled, visible results rather than
animation frames.

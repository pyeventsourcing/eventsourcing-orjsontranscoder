# -*- coding: utf-8 -*-
import eventsourcing_orjsontranscoder


def test_eventsourcing_orjsontranscoder() -> None:
    assert eventsourcing_orjsontranscoder


def test_import_eventsourcing() -> None:
    import eventsourcing

    assert eventsourcing.__version__

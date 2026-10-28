import importlib.util
import json
from pathlib import Path
import pytest
ROOT=Path(__file__).parents[1]
spec=importlib.util.spec_from_file_location('restore_v11',ROOT/'ops/rollback/restore_v11.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
manifest=json.loads((ROOT/'ops/rollback/v11.json').read_text())


def test_default_restore_is_private_and_never_changes_policy():
    command=m.restore_command(manifest,'vyoora-v11-rollback-drill','1')
    assert '--no-allow-unauthenticated' in command
    assert any('AI_ENABLED=false' in arg for arg in command)
    assert any(manifest['image'] in arg for arg in command)
    assert not any('update-traffic' in arg or 'set_ai_policy' in arg for arg in command)


def test_production_requires_explicit_staging_and_never_moves_traffic():
    with pytest.raises(ValueError):m.restore_command(manifest,manifest['productionService'],'1')
    command=m.restore_command(manifest,manifest['productionService'],'2',production_staging=True)
    assert '--no-traffic' in command
    assert any('vyoora-openai-api-key:2' in arg for arg in command)
    assert '--no-allow-unauthenticated' not in command


@pytest.mark.parametrize('version',['latest','0','-1','not-a-version'])
def test_restore_refuses_unpinned_or_invalid_secret(version):
    with pytest.raises(ValueError):m.restore_command(manifest,'isolated-drill',version)

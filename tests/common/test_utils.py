import pytest
from unittest.mock import patch, MagicMock
import pandas as pd
import json

from src.common.utils.s3_utils import s3_util


# -----------------------------------------------------
# Fixtures
# -----------------------------------------------------
@pytest.fixture
def sample_df():
    return pd.DataFrame({'name': ['홍길동', '이순신'], 'age': [30, 55]})


@pytest.fixture
@patch("src.common.utils.s3_utils.boto3.client")
def util(mock_boto_client):
    mock_s3 = MagicMock()
    mock_boto_client.return_value = mock_s3
    return s3_util(ymd='2025-12-12', hm='1230', bucket='test_bucket')


# -----------------------------------------------------
# Test: pandas upload
# -----------------------------------------------------
def test_upload_pandas(util, sample_df):
    util.upload(sample_df, folder='raw-data', format='csv')

    util.s3.put_object.assert_called_once()
    _, kwargs = util.s3.put_object.call_args
    assert kwargs["Bucket"] == "test_bucket"
    assert "raw-data/2025-12-12/1230.csv" in kwargs["Key"]
    assert isinstance(kwargs["Body"], bytes)


# -----------------------------------------------------
# Test: JSON upload
# -----------------------------------------------------
def test_upload_json(util):
    util.upload({"a": 1, "b": 2}, folder="json-data")

    util.s3.put_object.assert_called_once()
    _, kwargs = util.s3.put_object.call_args
    assert kwargs["Bucket"] == "test_bucket"
    assert "json-data/2025-12-12/1230.json" in kwargs["Key"]


# -----------------------------------------------------
# Test: JSON read
# -----------------------------------------------------
def test_read_json(util):
    mock_body = MagicMock()
    mock_body.read.return_value = json.dumps({"x": 10, "y": 20}).encode("utf-8")
    util.s3.get_object = MagicMock(return_value={"Body": mock_body})

    df = util.read("json-folder/sample.json", input_type="json", return_type="pandas_df")

    assert df.iloc[0]["x"] == 10
    assert df.iloc[0]["y"] == 20


# -----------------------------------------------------
# Test: Parquet read
# -----------------------------------------------------
@patch("pyarrow.dataset.dataset")
def test_read_parquet(mock_dataset, util):
    mock_table = MagicMock()
    mock_table.to_pandas.return_value = {"dummy": "data"}
    mock_dataset.return_value.to_table.return_value = mock_table

    result = util.read("raw/data.parquet")

    assert result == {"dummy": "data"}


# -----------------------------------------------------
# Test: invalid input type
# -----------------------------------------------------
def test_read_invalid_input_type(util):
    with pytest.raises(ValueError):
        util.read("raw/a.txt", input_type="xml")


# -----------------------------------------------------
# Test: invalid return type
# -----------------------------------------------------
@patch("pyarrow.dataset.dataset")
def test_read_invalid_return_type(mock_dataset, util):
    mock_table = MagicMock()
    mock_dataset.return_value.to_table.return_value = mock_table

    with pytest.raises(ValueError):
        util.read("raw/a.parquet", return_type="spark_df")

# coding: utf-8

from __future__ import absolute_import

from flask import json
from six import BytesIO

from openapi_server.models.instance_type import InstanceType  # noqa: E501
from openapi_server.test import BaseTestCase


class TestTypesController(BaseTestCase):
    """TypesController integration test stubs"""

    def test_delete_type(self):
        """Test case for delete_type

        Delete an instance type
        """
        response = self.client.open(
            '//types/{type_id}'.format(type_id=56),
            method='DELETE')
        self.assert200(response,
                       'Response body is : ' + response.data.decode('utf-8'))

    def test_get_type(self):
        """Test case for get_type

        Get an instance type
        """
        response = self.client.open(
            '//types/{type_id}'.format(type_id=56),
            method='GET')
        self.assert200(response,
                       'Response body is : ' + response.data.decode('utf-8'))

    def test_get_types(self):
        """Test case for get_types

        Get instance types
        """
        response = self.client.open(
            '//types',
            method='GET')
        self.assert200(response,
                       'Response body is : ' + response.data.decode('utf-8'))

    def test_patch_type(self):
        """Test case for patch_type

        Update an instance type
        """
        body = InstanceType()
        response = self.client.open(
            '//types/{type_id}'.format(type_id=56),
            method='PATCH',
            data=json.dumps(body),
            content_type='application/json')
        self.assert200(response,
                       'Response body is : ' + response.data.decode('utf-8'))

    def test_post_type(self):
        """Test case for post_type

        Add a new instance type
        """
        body = InstanceType()
        response = self.client.open(
            '//types',
            method='POST',
            data=json.dumps(body),
            content_type='application/json')
        self.assert200(response,
                       'Response body is : ' + response.data.decode('utf-8'))


if __name__ == '__main__':
    import unittest
    unittest.main()

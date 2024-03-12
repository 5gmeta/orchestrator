# coding: utf-8

from __future__ import absolute_import

from flask import json
from six import BytesIO

from openapi_server.models.instance import Instance  # noqa: E501
from openapi_server.test import BaseTestCase


class TestInstancesController(BaseTestCase):
    """InstancesController integration test stubs"""

    def test_delete_instance(self):
        """Test case for delete_instance

        Delete an instance
        """
        response = self.client.open(
            '//instances/{instance_id}'.format(instance_id='instance_id_example'),
            method='DELETE')
        self.assert200(response,
                       'Response body is : ' + response.data.decode('utf-8'))

    def test_get_instance(self):
        """Test case for get_instance

        Get a specific instance information
        """
        response = self.client.open(
            '//instances/{instance_id}'.format(instance_id='instance_id_example'),
            method='GET')
        self.assert200(response,
                       'Response body is : ' + response.data.decode('utf-8'))

    def test_get_instances(self):
        """Test case for get_instances

        Get the deployed instances
        """
        response = self.client.open(
            '//instances',
            method='GET')
        self.assert200(response,
                       'Response body is : ' + response.data.decode('utf-8'))

    def test_post_instance(self):
        """Test case for post_instance

        Deploy a pipeline instance
        """
        body = Instance()
        response = self.client.open(
            '//instances',
            method='POST',
            data=json.dumps(body),
            content_type='application/json')
        self.assert200(response,
                       'Response body is : ' + response.data.decode('utf-8'))


if __name__ == '__main__':
    import unittest
    unittest.main()

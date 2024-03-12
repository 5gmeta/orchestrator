#import connexion
#import six

from openapi_server.config.config import db
from openapi_server.models.instance_type import InstanceType, InstanceTypeSchema # noqa: E501
#from openapi_server import util

from sqlalchemy.exc import IntegrityError


def post_type(payload):  # noqa: E501
    """Add a new instance type

     # noqa: E501

    :param body: Type object that needs to be added
    :type body: dict | bytes

    :rtype: InstanceType
    """
#    if connexion.request.is_json:
#        body = InstanceType.from_dict(connexion.request.get_json())  # noqa: E501

    #type = InstanceType.query.filter(InstanceType.type_name == payload["type_name"]).one_or_none()

    #if type is None:
    try:
        schema = InstanceTypeSchema()

        # Deserialize the received data
        new_type = schema.load(payload)

        # Add the instance type to the database
        db.session.add(new_type)
        db.session.commit()

        # Serialize and return the newly created instance type in the response
        data = schema.dump(new_type)

        return data, 200
#    else:
    except IntegrityError:
        return "The instance type already exists", 402

def get_types():  # noqa: E501
    """Get instance types

    Get instance types # noqa: E501


    :rtype: InstanceType
    """
    types = InstanceType.query.all()

    types_schema = InstanceTypeSchema(many=True)

    data = types_schema.dump(types)

    return data, 200



def get_type(type_id):  # noqa: E501
    """Get an instance type

    Returns a single instance type # noqa: E501

    :param type_id: Specify the type id to get information about the instance type
    :type type_id: int

    :rtype: InstanceType
    """
    try:
        type = InstanceType.query.filter(InstanceType.type_id == type_id).one()

        type_schema = InstanceTypeSchema()

        data = type_schema.dump(type)

        return data, 200
    except:
        return "Instance type not found", 404


def patch_type(payload, type_id):  # noqa: E501
    """Update an instance type

     # noqa: E501

    :param body: 
    :type body: dict | bytes
    :param type_id: Specify the type id to modify the instance type and/or the resources
    :type type_id: int

    :rtype: InstanceType
    """
    try:
        old_type = InstanceType.query.filter(InstanceType.type_id == type_id).one()

        schema = InstanceTypeSchema()

        new_type = schema.load(payload)

        new_type.type_id = old_type.type_id

        db.session.merge(new_type)
        db.session.commit()

        data = schema.dump(new_type)

        return data, 200
    except:
        return "Instance type not found", 404


def delete_type(type_id):  # noqa: E501
    """Delete an instance type

     # noqa: E501

    :param type_id: Specify the type id to delete the instance type
    :type type_id: int

    :rtype: InstanceType
    """
    try:
        type = InstanceType.query.filter(InstanceType.type_id == type_id).one()

        db.session.delete(type)

        db.session.commit()

        return "Instance type successfully deleted", 200
    except:
        return "Instance type not found", 404
        
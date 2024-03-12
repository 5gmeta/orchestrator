import os
import connexion

from flask_sqlalchemy import SQLAlchemy
from flask_marshmallow import Marshmallow
from sqlalchemy_utils import database_exists, create_database

# Create the Connexion application instance
connexion_app = connexion.App(__name__, specification_dir='../openapi/')
app = connexion_app.app

database = 'mysql+pymysql://root:' + os.getenv('db_root_password') + '@' + os.getenv("db_host") + '/' + os.getenv("db_name")

# Check if the database exists, if not create it
if not database_exists(database):
    create_database(database)

# Configure the SQLAlchemy part of the app instance
app.config['SQLALCHEMY_ECHO'] = True
app.config['SQLALCHEMY_DATABASE_URI'] = database
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# Create the SQLAlchemy db instance
db = SQLAlchemy(app)

# Initialize Marshmallow
ma = Marshmallow(app)

# Check if database's tables exists, if not create them
if not db.inspect(db.engine).has_table("type") or not db.inspect(db.engine).has_table("instance"):
    from openapi_server.models.instance_type import InstanceType
    from openapi_server.models.instance import Instance
    db.create_all()
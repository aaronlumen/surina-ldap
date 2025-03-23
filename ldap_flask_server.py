from flask import Flask, request, jsonify, render_template_string
import subprocess
import os
import base64

app = Flask(__name__)

LDAP_ADMIN_DN = "cn=admin,dc=example,dc=org"
LDAP_BASE_DN = "dc=example,dc=org"
LDAP_PASSWORD = "adminpassword"

HTML_FORM = '''
<!DOCTYPE html>
<html>
<head><title>LDAP Contact + Certificate</title></head>
<body>
  <h2>Add Contact</h2>
  <form method="post" enctype="multipart/form-data">
    Name: <input type="text" name="cn"><br>
    Surname: <input type="text" name="sn"><br>
    Email: <input type="email" name="mail"><br>
    Certificate (.crt): <input type="file" name="certificate"><br>
    <input type="submit" value="Add Contact">
  </form>
</body>
</html>
'''

@app.route('/', methods=['GET', 'POST'])
def add_entry():
    if request.method == 'POST':
        cn = request.form['cn']
        sn = request.form['sn']
        mail = request.form['mail']
        cert_file = request.files['certificate']

        cert_path = f"/tmp/{cn.replace(' ', '_')}.crt"
        cert_file.save(cert_path)

        ldif_content = f"""
dn: cn={cn},{LDAP_BASE_DN}
objectClass: inetOrgPerson
cn: {cn}
sn: {sn}
mail: {mail}
userCertificate;binary:< file://{cert_path}
"""

        with open("/tmp/contact.ldif", "w") as f:
            f.write(ldif_content)

        try:
            result = subprocess.run(
                ["ldapadd", "-x", "-D", LDAP_ADMIN_DN, "-w", LDAP_PASSWORD, "-f", "/tmp/contact.ldif"],
                capture_output=True,
                check=True
            )
            return f"<p>Success: Contact {cn} added.</p><pre>{result.stdout.decode()}</pre>"
        except subprocess.CalledProcessError as e:
            return f"<p>Error</p><pre>{e.stderr.decode()}</pre>"

    return render_template_string(HTML_FORM)

@app.route('/search')
def search():
    query = request.args.get('cn', '*')
    try:
        result = subprocess.run(
            ["ldapsearch", "-x", "-D", LDAP_ADMIN_DN, "-w", LDAP_PASSWORD, "-b", LDAP_BASE_DN, f"cn={query}"],
            capture_output=True,
            check=True
        )
        return f"<pre>{result.stdout.decode()}</pre>"
    except subprocess.CalledProcessError as e:
        return f"<p>Error</p><pre>{e.stderr.decode()}</pre>"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)

using System;
using System.Collections.Generic;
using System.Data;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using Npgsql;

namespace TicketHeaven
{
    public partial class Form1 : Form
    {
        public Form1()
        {
            InitializeComponent();
        }

        NpgsqlConnection connect = new NpgsqlConnection("server=localHost;port=5432;UserID=postgres;password=1234;database=TicketHeaven");

        private bool ValidateInputs()
        {
            List<string> errors = new List<string>();

            if (textBox2.Text.Length < 3 || textBox2.Text.Length > 20)
            {
                errors.Add("Username must be between 3 and 20 characters.");
            }

            if (textBox3.Text.Length < 3 || textBox3.Text.Length > 16)
            {
                errors.Add("Name must be between 3 and 16 characters.");
            }

            string emailPattern = @"^[^@\s]+@[^@\s]+\.[^@\s]+$";
            if (!Regex.IsMatch(textBox6.Text, emailPattern))
            {
                errors.Add("Email format is invalid. Please enter a valid email (e.g., abc@abc.abc). ");
            }

            if (!Regex.IsMatch(textBox4.Text, @"^\d{11}$"))
            {
                errors.Add("Phone number must be exactly 11 numeric digits.");
            }

            int age = CalculateAge(dateTimePicker1.Value);
            if (age < 18 || age > 100)
            {
                errors.Add("Age must be between 18 and 100 years.");
            }

            if (errors.Count > 0)
            {
                string errorMessage = string.Join("\n", errors);
                MessageBox.Show(errorMessage, "Validation Errors", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return false;
            }

            return true;
        }

        private int CalculateAge(DateTime birthDate)
        {
            int age = DateTime.Now.Year - birthDate.Year;
            if (DateTime.Now.Date < birthDate.AddYears(age)) age--;
            return age;
        }

        private bool IsDuplicate(string username, string email, string phoneNumber, int? userId = null)
        {
            string query = "SELECT COUNT(*) FROM member WHERE (username = @username OR email = @email OR phonenumber = @phonenumber)";
            if (userId != null)
            {
                query += " AND userid != @userid";
            }

            using (NpgsqlCommand cmd = new NpgsqlCommand(query, connect))
            {
                cmd.Parameters.AddWithValue("@username", username);
                cmd.Parameters.AddWithValue("@email", email);
                cmd.Parameters.AddWithValue("@phonenumber", phoneNumber);
                if (userId != null) cmd.Parameters.AddWithValue("@userid", userId.Value);

                connect.Open();
                int count = Convert.ToInt32(cmd.ExecuteScalar());
                connect.Close();

                return count > 0;
            }
        }

        private void button1_Click(object sender, EventArgs e)
        {
            string query = "SELECT * FROM member";
            NpgsqlDataAdapter adapt = new NpgsqlDataAdapter(query, connect);
            DataSet dataset = new DataSet();
            adapt.Fill(dataset);
            dataGridView1.DataSource = dataset.Tables[0];
        }

        private void button2_Click(object sender, EventArgs e)
        {
            if (!ValidateInputs()) return;

            if (IsDuplicate(textBox2.Text, textBox6.Text, textBox4.Text))
            {
                MessageBox.Show("Username, email, or phone number already exists. Please use unique values.", "Duplicate Entry", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            connect.Open();
            NpgsqlCommand command1 = new NpgsqlCommand("INSERT INTO member (username, name, email, phonenumber, dateofbirth) VALUES(@username, @name, @email, @phonenumber, @dateofbirth)", connect);
            command1.Parameters.AddWithValue("@username", textBox2.Text);
            command1.Parameters.AddWithValue("@name", textBox3.Text);
            command1.Parameters.AddWithValue("@email", textBox6.Text);
            command1.Parameters.AddWithValue("@phonenumber", textBox4.Text);
            command1.Parameters.AddWithValue("@dateofbirth", dateTimePicker1.Value.Date);

            command1.ExecuteNonQuery();
            connect.Close();
            MessageBox.Show("User insertion has been done successfully.", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private void button3_Click(object sender, EventArgs e)
        {
            if (!ValidateInputs()) return;

            int userId = int.Parse(textBox1.Text);

            if (IsDuplicate(textBox2.Text, textBox6.Text, textBox4.Text, userId))
            {
                MessageBox.Show("Username, email, or phone number already exists. Please use unique values.", "Duplicate Entry", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            connect.Open();
            string updateQuery = "UPDATE member SET username = @username, name = @name, email = @email, phonenumber = @phonenumber, dateofbirth = @dateofbirth WHERE userid = @userid";
            NpgsqlCommand updateCommand = new NpgsqlCommand(updateQuery, connect);

            updateCommand.Parameters.AddWithValue("@userid", userId);
            updateCommand.Parameters.AddWithValue("@username", textBox2.Text);
            updateCommand.Parameters.AddWithValue("@name", textBox3.Text);
            updateCommand.Parameters.AddWithValue("@email", textBox6.Text);
            updateCommand.Parameters.AddWithValue("@phonenumber", textBox4.Text);
            updateCommand.Parameters.AddWithValue("@dateofbirth", dateTimePicker1.Value.Date);

            int rowsAffected = updateCommand.ExecuteNonQuery();
            connect.Close();

            if (rowsAffected > 0)
            {
                MessageBox.Show("User has been updated successfully.", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            else
            {
                MessageBox.Show("No record found with the given ID.", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private void button4_Click(object sender, EventArgs e)
        {
            connect.Open();
            string deleteQuery = "DELETE FROM member WHERE userid = @userid";
            NpgsqlCommand deleteCommand = new NpgsqlCommand(deleteQuery, connect);
            deleteCommand.Parameters.AddWithValue("@userid", int.Parse(textBox1.Text));

            int rowsAffected = deleteCommand.ExecuteNonQuery();
            connect.Close();

            if (rowsAffected > 0)
            {
                MessageBox.Show("Record has been deleted successfully.", "Success", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            else
            {
                MessageBox.Show("No record found with the given ID.", "Error", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}

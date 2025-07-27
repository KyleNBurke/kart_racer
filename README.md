# Arcade Racer
An arcade racing game with an emphasis on environmental physics.

Click the image below for a demo of the physics solver.

[![YouTube Video](https://img.youtube.com/vi/ZpHo55XJ1fw/0.jpg)](https://www.youtube.com/watch?v=ZpHo55XJ1fw)

This project features a complete collision detection and resolution system using a sequential impulse solver.

In detail, the collisions are handled by
1. spatial partitioning all physics entities,
2. detecting nearby bodies with an axis aligned bounding box intersection check as the broadphase test,
3. detecting colliding bodies with the Gilbert–Johnson–Keerthi distance algorithm (GJK) as the nearphase test,
4. finding the minimum resolution vector with the expanding polytope algorithm (EPA),
5. finding the contact points of the collision manifold using Sutherland–Hodgman clipping algorithm and finally,
6. applying sequential impulses iteratively to separate the colliding bodies.

Click the image below for a demo of the AI.

[![YouTube Video](https://img.youtube.com/vi/1k3zN1yOzWg/0.jpg)](https://www.youtube.com/watch?v=1k3zN1yOzWg)
